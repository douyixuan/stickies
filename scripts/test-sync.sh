#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache build/bin
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/SyncContent.swift Stickies/SyncCoordinator.swift Tests/SyncFixtures.swift Tests/SyncTests.swift -o build/bin/sync-tests
build/bin/sync-tests

xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library Stickies/SyncContent.swift Stickies/SyncCoordinator.swift Stickies/FolderSyncTransport.swift Tests/SyncFixtures.swift Tests/FolderSyncTests.swift -o build/bin/folder-sync-tests
build/bin/folder-sync-tests
