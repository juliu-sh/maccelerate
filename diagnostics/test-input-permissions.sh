#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-permission-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -Wno-unused-function \
  diagnostics/test_input_permissions.c Sources/ISS/event_serialize.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/permissions"
"$test_dir/permissions"
