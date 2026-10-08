#!/bin/bash
set -euo pipefail

PRODUCT_NAME="Maccelerate"
EXPECTED_CHANNEL="official"
EXPECTED_ID="com.interversehq.Maccelerate"
case "${1:-}" in
  "") ;;
  --source) PRODUCT_NAME="Maccelerate Source"; EXPECTED_CHANNEL="source"; EXPECTED_ID="com.interversehq.Maccelerate.source" ;;
  *) echo "Usage: $0 [--source]" >&2; exit 1 ;;
esac
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG_NAME="${BUILD_DIR}/${PRODUCT_NAME}-${VERSION}.dmg"
[[ -d "${APP_BUNDLE}" ]] || {
  echo "Missing ${APP_BUNDLE}; run ./dist/build.sh first." >&2
  exit 1
}
CHANNEL=$(/usr/libexec/PlistBuddy -c "Print :MaccelerateBuildChannel" "${APP_BUNDLE}/Contents/Info.plist")
[[ "${CHANNEL}" == "${EXPECTED_CHANNEL}" ]] || {
  echo "Expected ${EXPECTED_CHANNEL} build, found ${CHANNEL}; refusing to package the wrong channel." >&2
  exit 1
}
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true)
BUNDLE_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleName" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true)
DISPLAY_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || true)
[[ "${BUNDLE_ID}" == "${EXPECTED_ID}" && "${BUNDLE_NAME}" == "${PRODUCT_NAME}" && "${DISPLAY_NAME}" == "${PRODUCT_NAME}" ]] || {
  echo "App identity does not match the ${EXPECTED_CHANNEL} channel; refusing to package it." >&2
  exit 1
}
STAGING_DIR=$(mktemp -d "${BUILD_DIR}/dmg-staging.XXXXXX")
trap 'rm -rf "${STAGING_DIR}"' EXIT

[[ -f "${APP_BUNDLE}/Contents/Resources/Assets.car" && \
   -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]] || {
  echo "App bundle has no icon; run ./dist/build.sh first." >&2
  exit 1
}
[[ -f "${APP_BUNDLE}/Contents/Resources/LICENSE" ]] || {
  echo "App bundle has no MIT license; run ./dist/build.sh first." >&2
  exit 1
}
[[ -f "${APP_BUNDLE}/Contents/Resources/LICENSES/InstantSpaceSwitcher-MIT.txt" ]] || {
  echo "App bundle has no upstream MIT license; run ./dist/build.sh first." >&2
  exit 1
}
[[ -f "${APP_BUNDLE}/Contents/Resources/NOTICE" ]] || {
  echo "App bundle has no attribution notice; run ./dist/build.sh first." >&2
  exit 1
}
[[ -f "${APP_BUNDLE}/Contents/Resources/LICENSES/Sparkle.txt" && \
   -d "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework" ]] || {
  echo "App bundle has no Sparkle framework or license; run ./dist/build.sh first." >&2
  exit 1
}

ditto "${APP_BUNDLE}" "${STAGING_DIR}/${PRODUCT_NAME}.app"
# License notices travel inside the app; keep the installer limited to drag-and-drop.
ln -s /Applications "${STAGING_DIR}/Applications"
rm -f "${DMG_NAME}"
hdiutil create -volname "${PRODUCT_NAME}" -srcfolder "${STAGING_DIR}" \
  -format UDZO -fs HFS+ -ov "${DMG_NAME}"
echo "DMG created: ${PWD}/${DMG_NAME}"
