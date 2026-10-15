#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/NoteModel.swift Tests/ModelTests.swift -o build/model-tests
build/model-tests
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/NoteModel.swift Stickies/LayoutEngine.swift Stickies/NotePalette.swift Stickies/NoteDragHint.swift Stickies/NoteStore.swift Stickies/NoteView.swift Tests/StoreModelTests.swift -o build/store-model-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-model.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
STICKIES_DATA_DIR="$TEST_DATA" build/store-model-tests
