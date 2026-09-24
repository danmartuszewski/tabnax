#!/bin/bash
set -euo pipefail
script_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
native_root="$(cd -- "$script_dir/../.." && pwd)"
audit_build="$(mktemp -d /private/tmp/tabnax-presenter-audit.XXXXXX)"
benchmark_source="$script_dir/PresenterBenchmark.swift"
for argument in "$@"; do
  if [ "$argument" = "--prepare" ]; then benchmark_source="$script_dir/PreparedPresenterBenchmark.swift"; fi
done
xcrun swiftc -O -whole-module-optimization -swift-version 6   -module-cache-path "$audit_build/ModuleCache" -emit-library -emit-module   -module-name TabnaxCore "$native_root"/Packages/TabnaxCore/Sources/TabnaxCore/*.swift   -emit-module-path "$audit_build/TabnaxCore.swiftmodule" -o "$audit_build/libTabnaxCore.dylib"
xcrun swiftc -O -whole-module-optimization -swift-version 6   -module-cache-path "$audit_build/ModuleCache" -I "$audit_build" -L "$audit_build"   -lTabnaxCore -Xlinker -rpath -Xlinker "$audit_build"   "$native_root/Tabnax/Support.swift" "$native_root/Tabnax/InputRouter.swift"   "$native_root/Tabnax/ModePresenter.swift" "$benchmark_source"   -o "$audit_build/presenter-benchmark"
if [ "$#" -eq 0 ]; then set -- canopy 30 --warm-assets; fi
"$audit_build/presenter-benchmark" "$@"
