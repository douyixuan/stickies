#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/bin build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library -target "$(uname -m)-apple-macosx14.0" \
    Stickies/StickyNote.swift Stickies/CompatibleNoteFile.swift Stickies/LosslessJSON.swift Stickies/LocalNoteTrash.swift Stickies/SerializedNoteCommands.swift Stickies/SegmentedCommandLedger.swift Stickies/LocalCommandSocket.swift Tools/Istk.swift -o build/bin/istk
