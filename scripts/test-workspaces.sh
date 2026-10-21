#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/WorkspaceTests.swift -o build/workspace-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-workspaces.XXXXXX")
trap 'rm -rf "$TEST_DATA"' EXIT
mkdir "$TEST_DATA/normal"
for phase in setup restart; do
    STICKIES_DATA_DIR="$TEST_DATA/normal" build/workspace-tests "$phase"
done
for phase in failure corrupt invalid stale; do
    mkdir "$TEST_DATA/$phase"
    STICKIES_DATA_DIR="$TEST_DATA/$phase" build/workspace-tests "$phase"
done
