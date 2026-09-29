#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/maccelerate-compat-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT
for name in os_compatibility horizontal_payload_policy hotkey_overlay_payload; do
  clang -std=c11 -Wall -Wextra -Werror -I Sources/ISS \
    "diagnostics/test_${name}.c" Sources/ISS/event_serialize.c \
    -framework ApplicationServices -framework CoreFoundation -framework IOKit \
    -o "$test_dir/$name"
  if [[ "$name" == os_compatibility ]]; then
    for mode in 0 1; do
      ISS_FORCE_EVENT_AUGMENTATION="$mode" ISS_EXPECT_EVENT_AUGMENTATION="$mode" "$test_dir/$name"
    done
  else
    "$test_dir/$name"
  fi
done
