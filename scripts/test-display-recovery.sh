#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/DisplayRecoveryTests.swift -o build/display-recovery-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-display.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
mkdir "$TEST_DATA/normal" "$TEST_DATA/failure"
for phase in setup restart; do
    STICKIES_DATA_DIR="$TEST_DATA/normal" build/display-recovery-tests "$phase"
done
STICKIES_DATA_DIR="$TEST_DATA/failure" build/display-recovery-tests failure
