#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-local.sh --app
export STICKIES_DATA_DIR="$PWD/build/preview-data"
exec open -n --env "STICKIES_DATA_DIR=$STICKIES_DATA_DIR" "$PWD/build/preview.noindex/iStickies2 Preview.app"
