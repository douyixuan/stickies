#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/LayoutStoreTests.swift -o build/layout-store-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-layout.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
mkdir "$TEST_DATA/normal" "$TEST_DATA/corrupt" "$TEST_DATA/failure" "$TEST_DATA/notes-failure"
for phase in setup restore verify; do
    STICKIES_DATA_DIR="$TEST_DATA/normal" build/layout-store-tests "$phase"
done
STICKIES_DATA_DIR="$TEST_DATA/corrupt" build/layout-store-tests corrupt
STICKIES_DATA_DIR="$TEST_DATA/failure" build/layout-store-tests failure
STICKIES_DATA_DIR="$TEST_DATA/notes-failure" build/layout-store-tests notes_failure
STICKIES_DATA_DIR="$TEST_DATA/notes-failure" build/layout-store-tests recover_notes_failure
