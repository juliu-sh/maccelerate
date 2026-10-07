#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-terminal-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-unused-function -I Sources/ISS \
  -Dsysctlbyname=trackpad_fixture_sysctlbyname \
  diagnostics/test_trackpad_terminal.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/terminal"
"$test_dir/terminal"
for product in 27.0.1 27.1 28.0; do
  "$test_dir/terminal" "$product" unknown
done
