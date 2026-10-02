#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-release-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-pointer-bool-conversion \
  -Wno-ignored-attributes -Wno-unused-function \
  -Dsysctlbyname=fixture_sysctlbyname \
  diagnostics/test_release_horizontal.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/release-horizontal"
"$test_dir/release-horizontal" 27.0 26A428 release
"$test_dir/release-horizontal" 27.0 26A5388g modern
"$test_dir/release-horizontal" 27.0 26A5406e modern
"$test_dir/release-horizontal" 27.0 26A429 modern
"$test_dir/release-horizontal" 28.0 27A1 modern
"$test_dir/release-horizontal" 27.0 unknown modern
"$test_dir/release-horizontal" 26.6 25G100 legacy
"$test_dir/release-horizontal" 13.0 22A380 legacy
