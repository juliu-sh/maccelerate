#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-rapid-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-pointer-bool-conversion -Wno-ignored-attributes -Wno-unused-function \
  diagnostics/test_rapid_switch.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit -o "$test_dir/rapid"
failed=0
for mode in 0 1; do
  for scenario in 0 1 2 3 4 5 6 8 9 10; do
    "$test_dir/rapid" "$mode" "$scenario" || failed=1
  done
  for scenario in 0 1 2 4 6 7; do
    "$test_dir/rapid" "$mode" "$scenario" fallback || failed=1
  done
done
exit "$failed"
