#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/CanvasBoardTests.swift -o build/canvas-board-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-board.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
mkdir "$TEST_DATA/normal" "$TEST_DATA/corrupt" "$TEST_DATA/failure"
STICKIES_DATA_DIR="$TEST_DATA/normal" build/canvas-board-tests setup
STICKIES_DATA_DIR="$TEST_DATA/normal" build/canvas-board-tests restore
STICKIES_DATA_DIR="$TEST_DATA/corrupt" build/canvas-board-tests corrupt
STICKIES_DATA_DIR="$TEST_DATA/failure" build/canvas-board-tests failure
