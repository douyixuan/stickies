#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-cli.sh
SOURCES=(Stickies/StickyNote.swift Stickies/CompatibleNoteFile.swift Stickies/LosslessJSON.swift Stickies/LocalNoteTrash.swift Stickies/SerializedNoteCommands.swift Stickies/SegmentedCommandLedger.swift)
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/SegmentedLedgerProbe.swift -o build/bin/segmented-ledger-probe
APP_SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || APP_SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${APP_SOURCES[@]}" Tests/SegmentedAppProbe.swift -o build/bin/segmented-app-probe
# Compile exact pre-migration sources. Only temporary exports, never another checkout.
OLD_EXPORT=$(mktemp -d /tmp/istk-old-writers-XXXXXX)
trap 'rm -rf "$OLD_EXPORT"' EXIT
for REVISION in c199a7a335c6d2e7f5b076e431efc23b7b101a6a fe5bf47e992e57fa7483f61645ba56f4d988cdac 74aec5511cb6d855913ba0a8f733f2a39f3a2978; do
    mkdir "$OLD_EXPORT/$REVISION"
    git archive "$REVISION" Stickies Tools | tar -x -C "$OLD_EXPORT/$REVISION"
    OLD_SOURCES=()
    for source in "$OLD_EXPORT/$REVISION"/Stickies/*.swift; do
        [[ "$source" == */StickiesApp.swift ]] || OLD_SOURCES+=("$source")
    done
    xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${OLD_SOURCES[@]}" Tests/OldWriterGateProbe.swift -o "build/bin/old-writer-$REVISION"
    if [[ "$REVISION" != c199a7a335c6d2e7f5b076e431efc23b7b101a6a ]]; then
        xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${OLD_SOURCES[@]}" "$OLD_EXPORT/$REVISION/Tools/Istk.swift" -o "build/bin/old-cli-$REVISION"
    fi
done
cp build/bin/old-cli-74aec5511cb6d855913ba0a8f733f2a39f3a2978 build/bin/istk-before-segments
python3 Tests/SegmentedLedgerTests.py
