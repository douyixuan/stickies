#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/CanvasTests.swift -o build/canvas-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-canvas.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
STICKIES_DATA_DIR="$TEST_DATA" build/canvas-tests
STICKIES_DATA_DIR="$TEST_DATA" build/canvas-tests --restore
