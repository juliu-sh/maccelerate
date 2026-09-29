#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-gesture-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -I Sources/ISS \
  diagnostics/test_gesture_recovery.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/test-gesture-recovery"
"$test_dir/test-gesture-recovery" 0
"$test_dir/test-gesture-recovery" 1
