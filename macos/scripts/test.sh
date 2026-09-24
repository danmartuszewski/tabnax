#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
export CLANG_MODULE_CACHE_PATH="$PWD/build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/build/ModuleCache"
swift test --package-path Packages/TabnaxCore --scratch-path build/core --cache-path build/spm-cache
xcodebuild -project Tabnax.xcodeproj -scheme TabnaxFixture -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
xcodebuild -project Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:TabnaxTests test
if [[ "${1:-}" == "--ui" ]]; then
  xcodebuild -project Tabnax.xcodeproj -scheme Tabnax -configuration Debug \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath build/UIDerivedData \
    TABNAX_APP_BUNDLE_IDENTIFIER=pl.tabnax.Tabnax.UITesting -only-testing:TabnaxUITests test
fi
