#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/bin
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/CompatibilityTests.swift -o build/compatibility-tests
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/StickyNote.swift Stickies/CompatibleNoteFile.swift Stickies/LosslessJSON.swift Tools/NoteDataCheck.swift -o build/bin/NoteDataCheck
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-compatibility.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
STICKIES_DATA_DIR="$TEST_DATA" build/compatibility-tests unit
before=$(shasum -a 256 "$TEST_DATA/notes.json")
build/bin/NoteDataCheck "$TEST_DATA/notes.json"
[[ "$before" == "$(shasum -a 256 "$TEST_DATA/notes.json")" ]]
[[ ! -e "$TEST_DATA/notes.lock" ]]
STICKIES_DATA_DIR="$TEST_DATA" build/compatibility-tests edit
STICKIES_DATA_DIR="$TEST_DATA" build/compatibility-tests restart
printf '{"schemaVersion":999}' > "$TEST_DATA/future.json"
if build/bin/NoteDataCheck "$TEST_DATA/future.json"; then exit 1; fi
