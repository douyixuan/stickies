#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/LayoutEngine.swift Stickies/NotePalette.swift Stickies/NoteDragHint.swift Stickies/NoteStore.swift Stickies/NoteView.swift Tests/StoreSmoke.swift -o build/store-smoke
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-test.XXXXXX")
export STICKIES_DATA_DIR="$TEST_DATA"
build/store-smoke
build/store-smoke --restore
printf 'Test data: %s\n' "$TEST_DATA"

build/store-smoke --hold &
HOLDER_PID=$!
trap 'kill "$HOLDER_PID" 2>/dev/null || true' EXIT
for attempt in {1..30}; do
    [[ -f "$TEST_DATA/ready" ]] && break
    sleep 0.1
done
[[ -f "$TEST_DATA/ready" ]]
build/store-smoke --lock-probe
kill "$HOLDER_PID"
wait "$HOLDER_PID" 2>/dev/null || true
trap - EXIT
