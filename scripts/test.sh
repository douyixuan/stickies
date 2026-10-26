#!/bin/bash
# The whole core suite: data, migration, layout geometry, failure recovery.
# No windows, no network, no Xcode project — one compile and one run.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
xcrun swiftc -swift-version 5 \
    -module-cache-path "$PWD/build/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" \
    Stickies/Core/*.swift Tests/*.swift \
    -o build/core-tests
exec build/core-tests
