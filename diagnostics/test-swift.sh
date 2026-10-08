#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash diagnostics/test-input-permissions.sh
bash diagnostics/test-gesture-recovery.sh
bash diagnostics/test-vertical-middle-click.sh
bash diagnostics/test-async-switch.sh
bash diagnostics/test-compatibility.sh
bash diagnostics/test-release-horizontal.sh
bash diagnostics/test-trackpad-payload.sh
bash diagnostics/test-trackpad-terminal.sh
bash diagnostics/test-trackpad-recovery.sh

# Keep Swift/Clang module caches in a writable location on restricted Macs.
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/maccelerate-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"

TESTING_PLUGIN="$(xcode-select -p)/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
if [[ -f "$TESTING_PLUGIN" ]]; then
  # Some Command Line Tools builds omit TestingMacros from SwiftPM's plugin map.
  swift test --disable-sandbox -Xswiftc -load-plugin-library -Xswiftc "$TESTING_PLUGIN" "$@"
else
  swift test --disable-sandbox "$@"
fi
