#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-async-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
flags=(-std=c11 -Wall -Wextra -Werror -Wno-pointer-bool-conversion -Wno-ignored-attributes -Wno-unused-function)
frameworks=(-framework ApplicationServices -framework CoreFoundation -framework IOKit)
clang "${flags[@]}" diagnostics/test_async_switch.c Sources/ISS/event_serialize.c "${frameworks[@]}" -o "$test_dir/async"
ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD=0 "$test_dir/async"
ISS_FORCE_INSTANT_HORIZONTAL_PAYLOAD=1 "$test_dir/async"
clang "${flags[@]}" -DLEGACY_TRACE diagnostics/test_async_switch.c Sources/ISS/event_serialize.c "${frameworks[@]}" -o "$test_dir/legacy"
"$test_dir/legacy" > "$test_dir/legacy.txt"
diff -u diagnostics/macos26-baseline.txt "$test_dir/legacy.txt"
echo 'PASS: macOS 26 event trace, return values and callbacks match the preserved baseline'
