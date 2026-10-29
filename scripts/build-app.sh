#!/bin/bash
# Builds the real app you can keep: build/iStickies2.app, ad-hoc signed only.
# It uses your normal notes in ~/Library/Application Support/Stickies.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null; then
    echo 'xcodegen is required: brew install xcodegen' >&2
    exit 1
fi
xcodegen generate
xcodebuild -project Stickies.xcodeproj -scheme Stickies -configuration Release \
    -derivedDataPath build/.xcode.noindex \
    CODE_SIGNING_ALLOWED=NO build
BUILT="build/.xcode.noindex/Build/Products/Release/iStickies2.app"
rm -rf build/iStickies2.app
cp -R "$BUILT" build/iStickies2.app
# Ship the CLI from this same checkout before signing the complete bundle.
bash scripts/build-cli.sh
cp build/bin/istk build/iStickies2.app/Contents/MacOS/istk
codesign --force --deep --sign - build/iStickies2.app
codesign --verify --deep --strict build/iStickies2.app
echo
echo "Built build/iStickies2.app"
echo "Drag it to /Applications to keep it. First launch: right-click > Open (it is not notarized)."

cat <<'USAGE'
CLI (from this checkout; no PATH changes):
  cli="$PWD/build/iStickies2.app/Contents/MacOS/istk"
  "$cli" help
  "$cli" version
  profile="$(mktemp -d -t istk-demo)"
  "$cli" --dir "$profile" add 'Example note'
  "$cli" --dir "$profile" list
Keep both paths quoted, including when the app path contains spaces.
Every data command requires --dir; it never selects the app's default profile.
Use only this synthetic profile for a trial. This example does not launch the app.
USAGE
