#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-payload-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
clang -std=c11 -Wall -Wextra -Werror -fsanitize=address,undefined \
  diagnostics/test_trackpad_payload.c \
  -framework ApplicationServices -framework CoreFoundation -framework IOKit \
  -o "$test_dir/payload"
"$test_dir/payload"
