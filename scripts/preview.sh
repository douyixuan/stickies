#!/bin/bash
# Builds and launches a developer preview with its own notes in build/preview-data,
# so trying a change never touches your real notes. No Xcode project, no signing.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/preview.noindex/iStickies2 Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/module-cache

xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "$PWD/build/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" \
    Stickies/Core/*.swift Stickies/App/*.swift \
    -o "$APP/Contents/MacOS/StickiesPreview"
cp Assets/iStickies2.icns "$APP/Contents/Resources/iStickies2.icns"

STICKIES_PREVIEW_APP="$APP" STICKIES_PREVIEW_DATA="$PWD/build/preview-data" python3 - <<'PYPLIST'
import os, pathlib, plistlib
info = {
    'CFBundleExecutable': 'StickiesPreview',
    'CFBundleIdentifier': 'dev.douyixuan.stickies.local-preview',
    'CFBundleName': 'iStickies2 Preview',
    'CFBundleDisplayName': 'iStickies2 Preview',
    'CFBundleIconFile': 'iStickies2.icns',
    'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '1.0.0',
    'CFBundleVersion': '1.0.0',
    'LSEnvironment': {'STICKIES_DATA_DIR': os.environ['STICKIES_PREVIEW_DATA']},
    'LSMinimumSystemVersion': '14.0',
}
path = pathlib.Path(os.environ['STICKIES_PREVIEW_APP']) / 'Contents/Info.plist'
path.write_bytes(plistlib.dumps(info))
PYPLIST

if [[ "${1:-}" == "--build-only" ]]; then
    echo "Built $APP (not launched)"
    exit 0
fi
exec open -n --env "STICKIES_DATA_DIR=$PWD/build/preview-data" "$APP"
