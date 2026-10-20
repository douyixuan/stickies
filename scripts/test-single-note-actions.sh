#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/bin
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/SingleNoteActionTests.swift -o build/bin/single-note-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-single-XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
for phase in setup restart legacy failure unsaved corrupt import; do
    profile="$TEST_DATA/$phase"
    [[ "$phase" == restart ]] && profile="$TEST_DATA/setup"
    mkdir -p "$profile"
    STICKIES_DATA_DIR="$profile" build/bin/single-note-tests "$phase"
done
