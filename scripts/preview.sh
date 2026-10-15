#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-local.sh
export STICKIES_DATA_DIR="$PWD/build/preview-data"
exec build/Stickies.app/Contents/MacOS/Stickies
