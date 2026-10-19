#!/bin/bash
# Build and package only. Never launches, installs or accesses note data.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -n "$(git status --porcelain --untracked-files=normal -- . ':!Stickies.xcodeproj')" ]]; then
    echo 'Refusing to stamp a dirty source tree. Commit the reviewed changes first.' >&2
    exit 1
fi
RELEASE_COMMIT=$(git rev-parse HEAD)
RELEASE_SHORT=$(git rev-parse --short=12 HEAD)
RELEASE_VERSION=0.2.1
RELEASE_BUILD="0.2.$(git rev-list --count HEAD)"
RELEASE_NAME="iStickies2-${RELEASE_VERSION}-${RELEASE_SHORT}-universal2"
RELEASE_ROOT="$PWD/build/releases"
mkdir -p "$RELEASE_ROOT" build/module-cache build/.artifacts.noindex
if [[ -e "$RELEASE_ROOT/$RELEASE_NAME" || -e "$RELEASE_ROOT/$RELEASE_NAME.zip" ]]; then
    echo "Release already exists; refusing to overwrite $RELEASE_NAME" >&2
    exit 1
fi
RELEASE_STAGE=$(mktemp -d "$PWD/build/.artifacts.noindex/release.XXXXXX")
trap 'rm -rf "$RELEASE_STAGE"' EXIT
PACKAGE="$RELEASE_STAGE/$RELEASE_NAME"
APP="$PACKAGE/payload"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for architecture in arm64 x86_64; do
    xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library \
        -target "${architecture}-apple-macosx14.0" Stickies/*.swift -o "$RELEASE_STAGE/Stickies-$architecture"
done
lipo -create "$RELEASE_STAGE/Stickies-arm64" "$RELEASE_STAGE/Stickies-x86_64" -output "$APP/Contents/MacOS/Stickies"
export STICKIES_RELEASE_APP="$APP" STICKIES_RELEASE_COMMIT="$RELEASE_COMMIT" STICKIES_RELEASE_VERSION="$RELEASE_VERSION" STICKIES_RELEASE_BUILD="$RELEASE_BUILD"
python3 - <<'PY'
import datetime, json, os, pathlib, plistlib
app = pathlib.Path(os.environ['STICKIES_RELEASE_APP'])
metadata = {
    'version': os.environ['STICKIES_RELEASE_VERSION'],
    'build': os.environ['STICKIES_RELEASE_BUILD'],
    'commit': os.environ['STICKIES_RELEASE_COMMIT'],
    'builtAtUTC': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'architectures': ['arm64', 'x86_64'],
    'minimumMacOS': '14.0',
    'signing': 'ad-hoc; no Developer ID or notarization',
    'defaultDataDirectory': '~/Library/Application Support/Stickies Delivery',
}
info = {
    'CFBundleExecutable': 'Stickies',
    'CFBundleIdentifier': 'dev.douyixuan.stickies.delivery',
    'CFBundleName': 'iStickies2',
    'CFBundleDisplayName': 'iStickies2',
    'CFBundlePackageType': 'APPL',
    'CFBundleIconFile': 'iStickies2.icns',
    'CFBundleShortVersionString': metadata['version'],
    'CFBundleVersion': metadata['build'],
    'StickiesGitCommit': metadata['commit'],
    'LSUIElement': True,
    'LSMinimumSystemVersion': '14.0',
}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
(app/'Contents/Resources/BuildInfo.json').write_text(json.dumps(metadata, indent=2)+'\n')
PY
cp Assets/iStickies2.icns "$APP/Contents/Resources/iStickies2.icns"
cp docs/DELIVERY.md "$PACKAGE/START-HERE.txt"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
python3 scripts/archive-delivery.py "$PACKAGE" "$RELEASE_ROOT/$RELEASE_NAME.zip" "$RELEASE_NAME"
python3 scripts/verify-delivery.py "$RELEASE_ROOT/$RELEASE_NAME.zip"
python3 Tests/ArchiveValidationTests.py "$RELEASE_ROOT/$RELEASE_NAME.zip"
(
    cd "$RELEASE_ROOT"
    shasum -a 256 "$RELEASE_NAME.zip" > "$RELEASE_NAME.zip.sha256"
)
printf 'Packaged (not launched): %s/%s.zip\n' "$RELEASE_ROOT" "$RELEASE_NAME"
