#!/bin/bash
set -euo pipefail

MASTER="dist/MaccelerateIcon-source.png"
SOURCE="dist/MaccelerateIcon.png"
ICONSET="dist/Maccelerate.iconset"
OUTPUT="dist/Maccelerate.icns"

[[ -f "${MASTER}" ]] || { echo "Missing icon master: ${MASTER}" >&2; exit 1; }
swift dist/prepare-icon.swift "${MASTER}" "${SOURCE}"
rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

for size in 16 32 128 256 512; do
  sips -s format png --resampleHeightWidth "${size}" "${size}" "${SOURCE}" \
    --out "${ICONSET}/icon_${size}x${size}.png" >/dev/null
  twice=$((size * 2))
  sips -s format png --resampleHeightWidth "${twice}" "${twice}" "${SOURCE}" \
    --out "${ICONSET}/icon_${size}x${size}@2x.png" >/dev/null
done

if ! iconutil -c icns "${ICONSET}" -o "${OUTPUT}"; then
  # Some Command Line Tools releases reject valid iconsets when writing ICNS.
  python3 dist/build-icns.py "${ICONSET}" "${OUTPUT}"
fi
echo "Icon created: ${OUTPUT}"
