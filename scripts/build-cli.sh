#!/bin/bash
# Builds build/bin/istk. The CLI shares the app's core and takes the same lock.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/bin build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library \
    -module-cache-path "$PWD/build/module-cache" \
    -target "$(uname -m)-apple-macosx14.0" \
    Stickies/Core/*.swift Tools/istk.swift \
    -o build/bin/istk
echo "Built build/bin/istk"
