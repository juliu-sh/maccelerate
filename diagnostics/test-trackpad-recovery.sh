#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-trackpad-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-unused-function \
  -Wno-pointer-bool-conversion -Wno-ignored-attributes \
  -Dsysctlbyname=trackpad_fixture_sysctlbyname \
  diagnostics/test_trackpad_recovery.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/recovery"
if [[ $# -gt 0 ]]; then
  "$test_dir/recovery" "$1"
else
  for mode in request stale matrix; do
    "$test_dir/recovery" "$mode"
    for product in 27.0.1 27.1 28.0; do
      "$test_dir/recovery" "$mode" "$product" unknown
    done
  done
fi
