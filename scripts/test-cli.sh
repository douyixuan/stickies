#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-cli.sh
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/CLIStoreTests.swift -o build/bin/cli-store-probe
python3 Tests/CLITests.py
