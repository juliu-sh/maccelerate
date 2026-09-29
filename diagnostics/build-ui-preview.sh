#!/bin/bash
# Build isolated copies of the real settings UI without starting global event taps.
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/maccelerate-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-sandbox
[[ -f dist/Maccelerate.icns ]] || bash dist/make-icon.sh
PREVIEW_BIN=$(swift build --show-bin-path --disable-sandbox)
for APPEARANCE in dark light; do
  PREVIEW_APP="output/Maccelerate Preview ${APPEARANCE}.app"
  rm -rf "$PREVIEW_APP"
  mkdir -p "$PREVIEW_APP/Contents/MacOS" "$PREVIEW_APP/Contents/Resources"
  cp "$PREVIEW_BIN/Maccelerate" "$PREVIEW_APP/Contents/MacOS/MacceleratePreview-${APPEARANCE}"
  cp dist/Maccelerate.icns "$PREVIEW_APP/Contents/Resources/Maccelerate-Glass.icns"
  cp Info.plist "$PREVIEW_APP/Contents/Info.plist"
  mkdir -p "$PREVIEW_APP/Contents/Frameworks"
  ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
    "$PREVIEW_APP/Contents/Frameworks/Sparkle.framework"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.interversehq.Maccelerate.preview.${APPEARANCE}" "$PREVIEW_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleExecutable MacceleratePreview-${APPEARANCE}" "$PREVIEW_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Maccelerate Preview ${APPEARANCE}" "$PREVIEW_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Maccelerate Preview ${APPEARANCE}" "$PREVIEW_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :MacceleratePreview bool true' "$PREVIEW_APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :MacceleratePreviewAppearance string ${APPEARANCE}" "$PREVIEW_APP/Contents/Info.plist"
  codesign --force --deep --sign - "$PREVIEW_APP"

done
