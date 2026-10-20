#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -gt 1 || ($# -eq 1 && "$1" != --run-gui) ]]; then
    echo 'Usage: test-store.sh [--run-gui]' >&2
    exit 64
fi
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/StoreSmoke.swift -o build/store-smoke
if [[ $# -eq 0 ]]; then
    echo 'Compiled GUI smoke harness. No GUI test ran.'
    exit 0
fi
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-test.XXXXXX")
export STICKIES_DATA_DIR="$TEST_DATA"
export STICKIES_GUI_SMOKE_TOKEN="$(uuidgen)"
printf '%s' "$STICKIES_GUI_SMOKE_TOKEN" > "$TEST_DATA/.gui-smoke-token"
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
