#!/bin/bash
# Builds build/bin/istk. The CLI shares the app's core and takes the same lock.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/bin build/module-cache
archs=${ISTK_BUILD_ARCHS:-$(uname -m)}
inputs=()
for arch in $archs; do
    case "$arch" in arm64|x86_64) ;; *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; esac
    xcrun swiftc -swift-version 5 -parse-as-library \
        -module-cache-path "$PWD/build/module-cache" \
        -target "$arch-apple-macosx14.0" \
        Stickies/Core/*.swift Tools/istk.swift -o "build/bin/istk-$arch"
    inputs+=("build/bin/istk-$arch")
done
[[ ${#inputs[@]} -gt 0 ]] || exit 1
if [[ ${#inputs[@]} -eq 1 ]]; then
    cp "${inputs[0]}" build/bin/istk
else
    xcrun lipo -create "${inputs[@]}" -output build/bin/istk
fi
echo "Built build/bin/istk ($archs)"
