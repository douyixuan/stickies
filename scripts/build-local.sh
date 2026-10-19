#!/bin/bash
# Default is compile-only: no discoverable .app. --app is an explicit developer preview.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ($# -eq 1 && "$1" != --app) ]]; then
    echo 'Usage: build-local.sh [--app]' >&2; exit 1
fi
mkdir -p build/bin build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library -target "$(uname -m)-apple-macosx14.0" Stickies/*.swift -o build/bin/StickiesPreview
if [[ $# -eq 0 ]]; then
    echo 'Compiled build/bin/StickiesPreview (not launched; no app bundle created)'; exit 0
fi
APP="$PWD/build/preview.noindex/iStickies2 Preview.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/bin/StickiesPreview "$APP/Contents/MacOS/StickiesPreview"
cp Assets/iStickies2.icns "$APP/Contents/Resources/iStickies2.icns"
export STICKIES_PREVIEW_APP="$APP" STICKIES_PREVIEW_DATA="$PWD/build/preview-data"
python3 - <<'PYPLIST'
import os, pathlib, plistlib
info = {
    'CFBundleExecutable': 'StickiesPreview',
    'CFBundleIdentifier': 'dev.douyixuan.stickies.local-preview',
    'CFBundleName': 'iStickies2 Preview', 'CFBundleDisplayName': 'iStickies2 Preview',
    'CFBundleIconFile': 'iStickies2.icns', 'CFBundlePackageType': 'APPL',
    'CFBundleShortVersionString': '0.2.1', 'CFBundleVersion': '0.2.1',
    'LSEnvironment': {'STICKIES_DATA_DIR': os.environ['STICKIES_PREVIEW_DATA']},
    'LSUIElement': True, 'LSMinimumSystemVersion': '14.0',
}
(pathlib.Path(os.environ['STICKIES_PREVIEW_APP'])/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
PYPLIST
printf 'Built explicit developer preview (not launched): %s\n' "$APP"
