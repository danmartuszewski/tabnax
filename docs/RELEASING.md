# Releasing Tabnax

Tabnax ships outside the Mac App Store. It needs cross-app Accessibility, Apple Events and a keyboard event tap, which the App Store sandbox does not allow. Direct distribution works like other menu-bar utilities (Rectangle, Raycast, Ice): a DMG on GitHub Releases, a Homebrew cask, and Sparkle for in-app updates.

## Signing modes

| Mode | When | What users see |
|---|---|---|
| **Self-signed** (current) | `APPLE_TEAM_ID` secret is unset | macOS blocks the first launch until the user clicks **Open Anyway** in Privacy & Security (the Homebrew cask clears the quarantine instead). The certificate never changes, so Accessibility permission survives updates. The Safari companion needs Safari's unsigned-extension setting. |
| **Developer ID** | `APPLE_TEAM_ID` and the notarization secrets are set | Opens normally; Safari companion works. Needs the paid Apple Developer Program. |

The self-signed certificate (`Tabnax Release Signing`, valid until 2046) is stored as the `SIGNING_P12_BASE64` / `SIGNING_P12_PASSWORD` secrets and in the maintainer's password manager. Losing it is recoverable: Sparkle accepts a new certificate because updates are also verified with the EdDSA key, but every user grants Accessibility again once.

To move to Developer ID: export the Developer ID Application certificate as a `.p12`, replace the two `SIGNING_P12_*` secrets, and add `APPLE_TEAM_ID`, `NOTARY_KEY_P8_BASE64`, `NOTARY_KEY_ID` and `NOTARY_ISSUER_ID`. The next release is notarized, the cask drops its quarantine step, and users update through Sparkle (granting Accessibility once more, since the signature changes).

```text
feat:/fix: commits on main
        │
        ▼
Release Please keeps a release PR open (version bump + CHANGELOG.md)
        │  maintainer merges the PR
        ▼
Tag vX.Y.Z + GitHub release
        │
        ▼
package job (macos-26, environment "release")
  archive → sign (self-signed, or Developer ID + notarize and staple) → DMG
  → Sparkle EdDSA signature → appcast.xml
        │
        ├─ Release assets: Tabnax-X.Y.Z.dmg, .sha256, Tabnax.dmg (stable name), appcast.xml
        └─ danmartuszewski/homebrew-tap: Casks/tabnax.rb
```

The website and README link to `https://github.com/danmartuszewski/tabnax/releases/latest/download/Tabnax.dmg`, which always serves the newest build. Installed copies read `https://github.com/danmartuszewski/tabnax/releases/latest/download/appcast.xml`, so publishing a release is all it takes to offer the update. Signing credentials exist only as secrets of the `release` environment; pull requests and forks never receive them.

## Versions

- The version lives in one place: `MARKETING_VERSION` in [`macos/Config/Tabnax.xcconfig`](../macos/Config/Tabnax.xcconfig). The app and the embedded Safari extension both inherit it. Release Please updates it; do not edit it by hand.
- Tags are `vMAJOR.MINOR.PATCH`. Tabnax stays on `0.x` while compatibility is still being validated. Before 1.0, `feat:` bumps the minor version, `fix:` bumps the patch version, and a breaking change (`feat!:`) also bumps the minor version.
- The release script derives `CFBundleVersion` as `major × 1,000,000 + minor × 1,000 + patch` (0.1.0 → 1000). Sparkle compares this number, so it must only grow. Minor and patch must stay below 1000.
- `TABNAX_SPARKLE_PUBLIC_KEY` in the same file is the public half of the update-signing key. Until it is set, builds hide **Check for Updates…**. The private half lives in the maintainer's login keychain (Sparkle `generate_keys --account tabnax`) and in the `SPARKLE_PRIVATE_KEY` secret. Losing it means installed copies can no longer verify updates.

## Verifying a download

Each release carries a `.sha256` file for its DMG. `codesign -dvv /Applications/Tabnax.app` should show `Authority=Tabnax Release Signing` (or, once notarized, `spctl -a -vv` reports `source=Notarized Developer ID`).

## Local builds

```sh
make dmg        # ad-hoc DMG in macos/build/release/, for local install testing only
```

Local DMGs are ad-hoc signed and are not suitable for distribution. The environment variables for signed local builds are listed at the top of [`macos/scripts/release.sh`](../macos/scripts/release.sh).

## Not yet covered

- **Firefox/Zen companion**: permanent installation needs an add-on signed by Mozilla. The release currently ships the Safari extension inside the app; the Gecko companion still needs the temporary development setup.
- **Delta updates and multiple channels** (beta, stable) are not configured. Every update downloads the full DMG.
- **dSYM symbol files** stay in the CI archive and are not uploaded.
