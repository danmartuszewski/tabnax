#!/bin/bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
native_root="$(cd -- "$script_dir/../.." && pwd)"
audit_build="$(mktemp -d /private/tmp/tabnax-opening-audit.XXXXXX)"
cp "$script_dir/OpeningBenchmark.swift" "$audit_build/"
mkdir "$audit_build/core"
if [ "$#" -gt 0 ]; then
    cp "$1/Support.swift" "$1/InputRouter.swift" "$audit_build/"
    cp "$1"/core/*.swift "$audit_build/core/"
    cp "$1/ModePresenter.original.swift" "$audit_build/ModePresenter.original.swift"
else
    cp "$native_root/Tabnax/Support.swift" "$native_root/Tabnax/InputRouter.swift" "$audit_build/"
    cp "$native_root"/Packages/TabnaxCore/Sources/TabnaxCore/*.swift "$audit_build/core/"
    cp "$native_root/Tabnax/ModePresenter.swift" "$audit_build/ModePresenter.original.swift"
fi
python3 "$script_dir/instrument.py" "$audit_build/ModePresenter.original.swift" "$audit_build/ModePresenter.swift"
xcrun swiftc -O -whole-module-optimization -swift-version 6 -module-cache-path "$audit_build/ModuleCache" -emit-library -emit-module -module-name TabnaxCore "$audit_build"/core/*.swift -emit-module-path "$audit_build/TabnaxCore.swiftmodule" -o "$audit_build/libTabnaxCore.dylib"
xcrun swiftc -O -whole-module-optimization -swift-version 6 -module-cache-path "$audit_build/ModuleCache" -I "$audit_build" -L "$audit_build" -lTabnaxCore -Xlinker -rpath -Xlinker "$audit_build" "$audit_build/Support.swift" "$audit_build/InputRouter.swift" "$audit_build/ModePresenter.swift" "$audit_build/OpeningBenchmark.swift" -o "$audit_build/opening-benchmark"
printf '%s\n' "$audit_build/opening-benchmark"
