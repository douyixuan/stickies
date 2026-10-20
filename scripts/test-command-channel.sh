#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/bin build/module-cache
bash scripts/build-cli.sh
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/CommandChannelHost.swift -o build/bin/command-channel-host
python3 Tests/CommandChannelTests.py
