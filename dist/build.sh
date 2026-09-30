#!/bin/bash
set -e

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/maccelerate-module-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$CLANG_MODULE_CACHE_PATH}"

CLEAN=false
BUILD_CONFIG="release"

for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=true ;;
    --debug) BUILD_CONFIG="debug" ;;
    --help)
      echo "Usage: $0 [--clean] [--debug] [--help]"
      echo ""
      echo "Options:"
      echo "  --clean    Delete build directory before building"
      echo "  --debug    Build in debug mode (default: release)"
      echo "  --help     Show this help message"
      exit 0
      ;;
  esac
done

PRODUCT_NAME="Maccelerate"
APP_NAME="Maccelerate"
BUILD_DIR="build"

if [[ "$CLEAN" == true ]]; then
  echo "Cleaning build directory..."
  rm -rf "${BUILD_DIR}"
fi

BUILD_PATH="${BUILD_DIR}/${BUILD_CONFIG}"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
BUILD_LOG_DIR="${PWD}/diagnostics/dist-build-logs"
mkdir -p "${BUILD_LOG_DIR}"

# Build arm64 and x86_64 in parallel
echo "Building arm64 and x86_64 in parallel..."
ARM64_LOG="${BUILD_LOG_DIR}/arm64-$$.log"
X86_LOG="${BUILD_LOG_DIR}/x86_64-$$.log"
: > "${ARM64_LOG}"
: > "${X86_LOG}"

# SwiftPM's current swiftbuild backend can fail while generating dSYM bundles
# under this toolchain. The native backend produces the same release binaries.
swift build -c "${BUILD_CONFIG}" --arch arm64  --build-path "${BUILD_DIR}/arm64"  --disable-sandbox --build-system native > "${ARM64_LOG}" 2>&1 &
PID_ARM64=$!
swift build -c "${BUILD_CONFIG}" --arch x86_64 --build-path "${BUILD_DIR}/x86_64" --disable-sandbox --build-system native > "${X86_LOG}"  2>&1 &
PID_X86=$!

printf "  arm64: starting...\n x86_64: starting...\n"
while kill -0 "${PID_ARM64}" 2>/dev/null || kill -0 "${PID_X86}" 2>/dev/null; do
    ARM_LINE=$(tail -1 "${ARM64_LOG}" 2>/dev/null)
    X86_LINE=$(tail -1 "${X86_LOG}"  2>/dev/null)
    printf "\033[2A\033[2K  arm64: %.110s\n\033[2K x86_64: %.110s\n" \
        "${ARM_LINE:-starting...}" "${X86_LINE:-starting...}"
    sleep 0.2
done

wait "${PID_ARM64}" && ARM64_STATUS=0 || ARM64_STATUS=$?
wait "${PID_X86}"   && X86_STATUS=0  || X86_STATUS=$?

[[ ${ARM64_STATUS} -eq 0 ]] && ARM_FINAL="done" || ARM_FINAL="FAILED"
[[ ${X86_STATUS}   -eq 0 ]] && X86_FINAL="done" || X86_FINAL="FAILED"
printf "\033[2A\033[2K  arm64: %s\n\033[2K x86_64: %s\n" "${ARM_FINAL}" "${X86_FINAL}"

if [[ ${ARM64_STATUS} -ne 0 ]]; then
    echo ""; echo "=== arm64 build output ==="; cat "${ARM64_LOG}"
fi
if [[ ${X86_STATUS} -ne 0 ]]; then
    echo ""; echo "=== x86_64 build output ==="; cat "${X86_LOG}"
fi
rm -f "${ARM64_LOG}" "${X86_LOG}"

[[ ${ARM64_STATUS} -eq 0 ]] || exit 1
[[ ${X86_STATUS}   -eq 0 ]] || exit 1

echo ""
echo "Creating universal binaries..."
mkdir -p "${BUILD_PATH}"
lipo -create \
  "${BUILD_DIR}/arm64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  "${BUILD_DIR}/x86_64/${BUILD_CONFIG}/${PRODUCT_NAME}" \
  -output "${BUILD_PATH}/${PRODUCT_NAME}"

lipo -create \
  "${BUILD_DIR}/arm64/${BUILD_CONFIG}/ISSCli" \
  "${BUILD_DIR}/x86_64/${BUILD_CONFIG}/ISSCli" \
  -output "${BUILD_PATH}/ISSCli"

# Remove Mach-O debug/object-file records before signing. SwiftPM otherwise
# embeds the builder's home and checkout paths even in release executables.
# This preserves executable code and exported symbols; dSYMs stay in build/.
if [[ "${BUILD_CONFIG}" == "release" ]]; then
  xcrun strip -S "${BUILD_PATH}/${PRODUCT_NAME}" "${BUILD_PATH}/ISSCli"
fi

echo ""
echo "Bundling..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"
cp "${BUILD_PATH}/${PRODUCT_NAME}" "${APP_BUNDLE}/Contents/MacOS/"
cp "${BUILD_PATH}/ISSCli" "${APP_BUNDLE}/Contents/MacOS/"
cp Info.plist "${APP_BUNDLE}/Contents/"
if [[ "${MACCELERATE_DISTRIBUTION:-0}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c 'Add :MaccelerateBuildChannel string official' "${APP_BUNDLE}/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c 'Add :MaccelerateBuildChannel string source' "${APP_BUNDLE}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.interversehq.Maccelerate.source' "${APP_BUNDLE}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Maccelerate Source' "${APP_BUNDLE}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Delete :SUFeedURL' "${APP_BUNDLE}/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "${APP_BUNDLE}/Contents/Info.plist"
fi
# Icon Composer owns the macOS corner mask and produces both the asset catalog
# and a legacy ICNS for the app's macOS 13 deployment target.
ICON_DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
if [[ ! -x "${ICON_DEVELOPER_DIR}/usr/bin/actool" ]]; then
  echo "Full Xcode is required to compile dist/icon-composer/AppIcon.icon." >&2
  exit 1
fi
DEVELOPER_DIR="${ICON_DEVELOPER_DIR}" xcrun actool \
  --compile "${APP_BUNDLE}/Contents/Resources" \
  --platform macosx --minimum-deployment-target 13.0 --target-device mac \
  --app-icon AppIcon \
  --output-partial-info-plist "${BUILD_DIR}/AppIcon-partial.plist" \
  --output-format human-readable-text --notices --warnings --errors \
  dist/icon-composer/AppIcon.icon
[[ -f "${APP_BUNDLE}/Contents/Resources/Assets.car" && \
   -f "${APP_BUNDLE}/Contents/Resources/AppIcon.icns" ]] || {
  echo "Icon Composer compilation did not produce the required app icons." >&2
  exit 1
}
cp LICENSE "${APP_BUNDLE}/Contents/Resources/LICENSE"
mkdir -p "${APP_BUNDLE}/Contents/Resources/LICENSES"
cp LICENSES/*.txt "${APP_BUNDLE}/Contents/Resources/LICENSES/"
cp NOTICE "${APP_BUNDLE}/Contents/Resources/NOTICE"
cp CREDITS.md "${APP_BUNDLE}/Contents/Resources/CREDITS.md"

SPARKLE_ROOT="${BUILD_DIR}/arm64/artifacts/sparkle/Sparkle"
mkdir -p "${APP_BUNDLE}/Contents/Frameworks"
ditto "${SPARKLE_ROOT}/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" \
  "${APP_BUNDLE}/Contents/Frameworks/Sparkle.framework"
mkdir -p "${BUILD_DIR}/sparkle-tools"
ditto "${SPARKLE_ROOT}/bin" "${BUILD_DIR}/sparkle-tools"

GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
echo "Injecting git SHA: ${GIT_SHA}"
/usr/libexec/PlistBuddy -c "Add :GitCommitHash string ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist" 2>/dev/null || \
/usr/libexec/PlistBuddy -c "Set :GitCommitHash ${GIT_SHA}" "${APP_BUNDLE}/Contents/Info.plist"

python3 dist/public_boundary.py --app "${APP_BUNDLE}"

echo ""
DEFAULT_SIGNING_IDENTITY="InstantSpaceSwitcher-27 Stable Local Code Signing"
SIGNING_IDENTITY="${MACCELERATE_CODESIGN_IDENTITY:-${ISS_CODESIGN_IDENTITY:-${DEFAULT_SIGNING_IDENTITY}}}"

if [[ "${MACCELERATE_DISTRIBUTION:-0}" == "1" ]]; then
  if [[ "${SIGNING_IDENTITY}" != "Developer ID Application:"* ]]; then
    echo "Distribution requires MACCELERATE_CODESIGN_IDENTITY with a Developer ID Application identity." >&2
    exit 1
  fi
  if ! security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
    echo "Developer ID signing identity is unavailable: ${SIGNING_IDENTITY}" >&2
    exit 1
  fi
  ./dist/sign-app.sh "${APP_BUNDLE}" "${SIGNING_IDENTITY}" --distribution
elif [[ "${SIGNING_IDENTITY}" == "-" ]]; then
  echo "Signing ad-hoc (explicitly requested)..."
  ./dist/sign-app.sh "${APP_BUNDLE}" -
elif security find-identity -v -p codesigning | grep -Fq "\"${SIGNING_IDENTITY}\""; then
  echo "Signing with stable identity: ${SIGNING_IDENTITY}"
  ./dist/sign-app.sh "${APP_BUNDLE}" "${SIGNING_IDENTITY}"
else
  echo "Signing identity unavailable; using ad-hoc signing for local distribution."
  ./dist/sign-app.sh "${APP_BUNDLE}" -
fi

echo ""
echo "App bundled at $(pwd)/${APP_BUNDLE} (${BUILD_CONFIG})"
