#!/bin/bash
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
DESTINATION="${1:?Pass an absolute path for the encrypted backup (.enc)}"
[[ "$DESTINATION" == /* && ! -e "$DESTINATION" ]] || {
  echo "Use a new absolute destination outside the source repository." >&2
  exit 1
}
case "$DESTINATION" in "$PWD"/*) echo "Backups must stay outside the source repository." >&2; exit 1;; esac
TOOL="build/sparkle-tools/generate_keys"
[[ -x "$TOOL" ]] || TOOL=".build/artifacts/sparkle/Sparkle/bin/generate_keys"
ACCOUNT=$(python3 -c 'import json; print(json.load(open("dist/release-config.json"))["sparkle_account"])')
TEMP_DIRECTORY=$(mktemp -d)
trap 'rm -rf "$TEMP_DIRECTORY"' EXIT
"$TOOL" --account "$ACCOUNT" -x "$TEMP_DIRECTORY/key"
echo "Choose a backup password at the OpenSSL prompt; it will not be shown."
echo "Save that password in your password manager."
if openssl enc -aes-256-cbc -pbkdf2 -iter 600000 -salt \
  -in "$TEMP_DIRECTORY/key" -out "$DESTINATION"; then
  chmod 600 "$DESTINATION"
  echo "Encrypted Sparkle-key backup saved: $DESTINATION"
else
  rm -f "$DESTINATION"
  exit 1
fi
# Restore outside the repo: openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000
# Then generate_keys --account maccelerate -f <decrypted-file>, and remove it.
