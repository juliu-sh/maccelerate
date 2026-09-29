#!/bin/bash
set -euo pipefail
APP="${1:?App bundle required}"
IDENTITY="${2:?Signing identity required}"
CODESIGN_ARGS=(--force --preserve-metadata=entitlements --sign "$IDENTITY")
if [[ "${3:-}" == "--distribution" ]]; then
  [[ "$IDENTITY" == "Developer ID Application:"* ]] || exit 1
  CODESIGN_ARGS+=(--options runtime --timestamp)
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
  codesign "${CODESIGN_ARGS[@]}" "$TARGET"
done
codesign --verify --deep --strict --verbose=2 "$APP"
