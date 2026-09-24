#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
configuration="${1:-Debug}"
xcodebuild -project Tabnax.xcodeproj -scheme Tabnax -configuration "$configuration" \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData build
print "Built: $PWD/build/DerivedData/Build/Products/$configuration/Tabnax.app"
