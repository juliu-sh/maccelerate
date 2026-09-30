#!/bin/bash
set -euo pipefail

# Creates a local, notarized release candidate. This script never publishes it.
cd "$(dirname "$0")/.."
python3 dist/release.py check-config
python3 dist/public_boundary.py --history

if [[ "${1:-}" != "--allow-dirty" && -n "$(git status --porcelain)" ]]; then
  echo "Commit or account for all working-tree changes before preparing a release." >&2
  exit 1
fi

IDENTITY="${MACCELERATE_CODESIGN_IDENTITY:-$(python3 dist/release.py config-value signing_identity)}"
PROFILE="${MACCELERATE_NOTARY_PROFILE:-$(python3 dist/release.py config-value notary_profile)}"
if [[ "${IDENTITY}" != "Developer ID Application:"* || -z "${PROFILE}" ]]; then
  echo "Set MACCELERATE_CODESIGN_IDENTITY to a Developer ID Application identity and MACCELERATE_NOTARY_PROFILE to a notarytool Keychain profile." >&2
  exit 1
fi
if ! security find-identity -v -p codesigning | grep -Fq "\"${IDENTITY}\""; then
  echo "Developer ID signing identity is unavailable: ${IDENTITY}" >&2
  exit 1
fi

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist)
DMG="build/Maccelerate-${VERSION}.dmg"
if [[ -d "build/release/${VERSION}" ]]; then
  echo "Candidate metadata for ${VERSION} exists; use a new version or archive the unpublished local trial first." >&2
  exit 1
fi
if git show-ref --verify --quiet "refs/tags/v${VERSION}"; then
  echo "Version v${VERSION} already has a Git tag; choose a new version." >&2
  exit 1
fi
if [[ -f "releases/maccelerate-${VERSION}/Maccelerate-${VERSION}.dmg" ]]; then
  echo "Version ${VERSION} already has a historical DMG; choose a new version." >&2
  exit 1
fi

MACCELERATE_CODESIGN_IDENTITY="$IDENTITY" MACCELERATE_DISTRIBUTION=1 ./dist/build.sh --clean
# Staple the app before packaging so it also carries an offline ticket.
ditto -c -k --keepParent build/Maccelerate.app build/Maccelerate-notarization.zip
notarize() {
  local archive="$1"
  local result="$2"
  xcrun notarytool submit "$archive" --keychain-profile "$PROFILE" --wait --output-format json > "$result"
  python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("Notarization:", d.get("status"), d.get("id")); sys.exit(0 if d.get("status") == "Accepted" else 1)' "$result"
}
notarize build/Maccelerate-notarization.zip build/app-notarization.json
xcrun stapler staple build/Maccelerate.app
xcrun stapler validate build/Maccelerate.app
./dist/deploy-to-dmg.sh
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
hdiutil verify "${DMG}"
notarize "$DMG" build/dmg-notarization.json
xcrun stapler staple "${DMG}"
xcrun stapler validate "${DMG}"
(
  cd build
  shasum -a 256 "Maccelerate-${VERSION}.dmg" > "Maccelerate-${VERSION}.sha256"
)

echo "Release candidate: ${DMG}"
echo "Checksum: build/Maccelerate-${VERSION}.sha256"
python3 dist/release.py assets
echo "Test this DMG on a clean Mac before creating tag v${VERSION} or publishing it."
