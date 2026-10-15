#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/WindowModeTests.swift -o build/window-mode-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-window-mode.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
mkdir "$TEST_DATA/normal" "$TEST_DATA/corrupt" "$TEST_DATA/failure"
STICKIES_DATA_DIR="$TEST_DATA/normal" build/window-mode-tests setup
STICKIES_DATA_DIR="$TEST_DATA/normal" build/window-mode-tests restore
STICKIES_DATA_DIR="$TEST_DATA/corrupt" build/window-mode-tests corrupt
STICKIES_DATA_DIR="$TEST_DATA/failure" build/window-mode-tests failure
