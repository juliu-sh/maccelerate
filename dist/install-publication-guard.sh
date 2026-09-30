#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f .public-free-repository ]] || { echo "Use the public Free checkout." >&2; exit 1; }
python3 dist/public_boundary.py --history
git config --local core.hooksPath dist/hooks
echo "Public Free pre-push guard installed for this checkout."
