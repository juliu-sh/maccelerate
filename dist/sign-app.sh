#!/bin/bash
set -euo pipefail
APP="${1:?App bundle required}"
IDENTITY="${2:?Signing identity required}"
OPTIONS=()
if [[ "${3:-}" == "--distribution" ]]; then
  [[ "$IDENTITY" == "Developer ID Application:"* ]] || exit 1
  OPTIONS=(--options runtime --timestamp)
fi
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
# Sign nested code first; never rely on --deep to sign a distribution build.
for TARGET in \
  "$FRAMEWORK/Versions/B/Autoupdate" \
  "$FRAMEWORK/Versions/B/Updater.app" \
  "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc" \
  "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc" \
  "$FRAMEWORK" \
  "$APP/Contents/MacOS/ISSCli" \
  "$APP"; do
  codesign --force "${OPTIONS[@]}" --preserve-metadata=entitlements --sign "$IDENTITY" "$TARGET"
done
codesign --verify --deep --strict --verbose=2 "$APP"
