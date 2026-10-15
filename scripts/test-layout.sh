#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" Stickies/LayoutEngine.swift Tests/main.swift -o build/layout-tests
build/layout-tests
