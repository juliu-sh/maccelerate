#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-middle-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-unused-function -I Sources/ISS \
  -Dsysctlbyname=middle_fixture_sysctlbyname \
  diagnostics/test_vertical_middle_click.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/middle"
for product in 26.6 26.6.1 27.0 27.0.1 27.1 28.0; do
  "$test_dir/middle" "$product"
done
