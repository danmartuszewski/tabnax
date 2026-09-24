#!/bin/zsh
# Archive, sign, notarize and package Tabnax as a DMG under macos/build/release/.
#
# Three signing modes, chosen from the environment (see docs/RELEASING.md):
#   ad-hoc        no TABNAX_SIGN_IDENTITY; for local install testing only.
#   self-signed   TABNAX_SIGN_IDENTITY names a self-signed code-signing certificate and
#                 TABNAX_TEAM_ID is unset. Not notarized, but the stable signature keeps
#                 Accessibility permission across updates.
#   developer-id  TABNAX_SIGN_IDENTITY e.g. "Developer ID Application: Name (TEAMID)" plus
#                 TABNAX_TEAM_ID. Add TABNAX_NOTARIZE=1 and either TABNAX_NOTARY_PROFILE (a
#                 `notarytool store-credentials` keychain profile) or NOTARY_KEY_PATH,
#                 NOTARY_KEY_ID and NOTARY_ISSUER_ID (API key).
# TABNAX_EXPECTED_VERSION, when set, must match MARKETING_VERSION (the release tag).
set -euo pipefail
cd "${0:A:h}/.."

version=$(sed -nE 's/^MARKETING_VERSION = ([0-9]+\.[0-9]+\.[0-9]+).*/\1/p' Config/Tabnax.xcconfig)
[[ -n $version ]] || { print -u2 "MARKETING_VERSION not found in Config/Tabnax.xcconfig"; exit 1 }
if [[ -n ${TABNAX_EXPECTED_VERSION:-} && $TABNAX_EXPECTED_VERSION != $version ]]; then
  print -u2 "Tag version $TABNAX_EXPECTED_VERSION does not match MARKETING_VERSION $version"
  exit 1
fi
build=$(python3 scripts/release_metadata.py build-number "$version")
identity=${TABNAX_SIGN_IDENTITY:--}
distributable=$([[ $identity != "-" ]] && print 1 || print 0)
developer_id=$([[ -n ${TABNAX_TEAM_ID:-} && $identity != "-" ]] && print 1 || print 0)
if (( ${TABNAX_NOTARIZE:-0} && ! developer_id )); then
  print -u2 "Notarization needs a Developer ID identity and TABNAX_TEAM_ID"
  exit 1
fi
public_key=$(sed -nE 's/^TABNAX_SPARKLE_PUBLIC_KEY = ([^ ]+).*/\1/p' Config/Tabnax.xcconfig)
if (( distributable )) && [[ -z $public_key ]]; then
  print -u2 "Set TABNAX_SPARKLE_PUBLIC_KEY in Config/Tabnax.xcconfig before a signed release"
  exit 1
fi

out=build/release
archive=$out/Tabnax.xcarchive
app=$out/export/Tabnax.app
dmg=$out/Tabnax-$version.dmg
rm -rf $out
mkdir -p $out/export

settings=(MARKETING_VERSION=$version CURRENT_PROJECT_VERSION=$build ENABLE_HARDENED_RUNTIME=YES)
if (( developer_id )); then
  settings+=(CODE_SIGN_STYLE=Manual "CODE_SIGN_IDENTITY=$identity" DEVELOPMENT_TEAM=$TABNAX_TEAM_ID OTHER_CODE_SIGN_FLAGS=--timestamp)
fi

print "Archiving Tabnax $version ($build)"
xcodebuild -project Tabnax.xcodeproj -scheme Tabnax -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath build/ReleaseDerivedData \
  -archivePath $archive archive $settings

if (( developer_id )); then
  cat > $out/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>developer-id</string>
<key>signingStyle</key><string>manual</string>
<key>signingCertificate</key><string>Developer ID Application</string>
<key>teamID</key><string>$TABNAX_TEAM_ID</string>
</dict></plist>
EOF
  # Export re-signs nested code (Safari extension, Sparkle helpers) for Developer ID.
  xcodebuild -exportArchive -archivePath $archive -exportPath $out/export -exportOptionsPlist $out/ExportOptions.plist
else
  ditto $archive/Products/Applications/Tabnax.app $app
fi
if (( distributable && ! developer_id )); then
  # Re-sign inside-out, keeping each target's entitlements. The hardened runtime is left
  # off: it is only required for notarization, and its library validation needs a Team ID.
  resign() { codesign --force --sign "$identity" --timestamp=none --preserve-metadata=entitlements "$1" }
  sparkle=$app/Contents/Frameworks/Sparkle.framework
  for nested in $sparkle/Versions/B/XPCServices/*.xpc(N) $sparkle/Versions/B/Autoupdate $sparkle/Versions/B/Updater.app \
      $sparkle $app/Contents/PlugIns/*.appex(N) $app; do
    if [[ -e $nested ]]; then resign $nested; fi
  done
fi
codesign --verify --deep --strict --verbose=2 $app

notarize() {
  if [[ -n ${TABNAX_NOTARY_PROFILE:-} ]]; then
    xcrun notarytool submit "$1" --wait --keychain-profile "$TABNAX_NOTARY_PROFILE"
  else
    xcrun notarytool submit "$1" --wait --key "${NOTARY_KEY_PATH:?}" --key-id "${NOTARY_KEY_ID:?}" --issuer "${NOTARY_ISSUER_ID:?}"
  fi
}
should_notarize=$(( distributable && ${TABNAX_NOTARIZE:-0} ))

if (( should_notarize )); then
  # Staple the app itself so it passes Gatekeeper offline after leaving the DMG.
  ditto -c -k --keepParent $app $out/Tabnax-notarize.zip
  notarize $out/Tabnax-notarize.zip
  xcrun stapler staple $app
  rm $out/Tabnax-notarize.zip
fi

staging=$out/dmg
mkdir -p $staging
ditto $app $staging/Tabnax.app
ln -s /Applications $staging/Applications
hdiutil create -volname "Tabnax $version" -srcfolder $staging -fs HFS+ -format UDZO -ov $dmg
rm -rf $staging

if (( developer_id )); then
  codesign --sign "$identity" --timestamp $dmg
fi
if (( should_notarize )); then
  notarize $dmg
  xcrun stapler staple $dmg
  spctl --assess --type open --context context:primary-signature --verbose=2 $dmg
  spctl --assess --type execute --verbose=2 $app
fi

(cd $out && shasum -a 256 ${dmg:t} > ${dmg:t}.sha256)
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  print "version=$version\nbuild=$build\ndmg=$PWD/$dmg" >> $GITHUB_OUTPUT
fi
(( distributable )) || print "Ad-hoc signed: for local testing only, not for distribution."
(( distributable && ! should_notarize )) && print "Not notarized: users approve the first launch in Privacy & Security."
print "Packaged: $PWD/$dmg"
