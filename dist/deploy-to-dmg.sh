#!/bin/bash
set -euo pipefail

PRODUCT_NAME="Maccelerate"
BUILD_DIR="build"
APP_BUNDLE="${BUILD_DIR}/${PRODUCT_NAME}.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG_NAME="${BUILD_DIR}/${PRODUCT_NAME}-${VERSION}.dmg"
STAGING_DIR=$(mktemp -d "${BUILD_DIR}/dmg-staging.XXXXXX")
trap 'rm -rf "${STAGING_DIR}"' EXIT

[[ -d "${APP_BUNDLE}" ]] || {
  echo "Missing ${APP_BUNDLE}; run ./dist/build.sh first." >&2
  exit 1
}
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
