#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/module-cache
SOURCES=()
for source in Stickies/*.swift; do
    [[ "$source" == "Stickies/StickiesApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library "${SOURCES[@]}" Tests/DeliveryRecoveryTests.swift -o build/delivery-recovery-tests
TEST_DATA=$(mktemp -d "${TMPDIR:-/tmp}/stickies-delivery-test.XXXXXX")
HOLDER_PID=""
cleanup() {
    if [[ -n "$HOLDER_PID" ]]; then kill "$HOLDER_PID" 2>/dev/null || true; fi
    rm -rf "$TEST_DATA"
}
trap cleanup EXIT
mkdir "$TEST_DATA/hardlink_v3" "$TEST_DATA/hardlink_v2" "$TEST_DATA/hardlink" "$TEST_DATA/retry" "$TEST_DATA/crash" "$TEST_DATA/corrupt" "$TEST_DATA/future"
STICKIES_DATA_DIR="$TEST_DATA/hardlink" build/delivery-recovery-tests hardlink
STICKIES_DATA_DIR="$TEST_DATA/hardlink" build/delivery-recovery-tests hardlink_reload
STICKIES_DATA_DIR="$TEST_DATA/hardlink_v2" build/delivery-recovery-tests hardlink_v2
STICKIES_DATA_DIR="$TEST_DATA/hardlink_v2" build/delivery-recovery-tests hardlink_v2_reload
STICKIES_DATA_DIR="$TEST_DATA/hardlink_v3" build/delivery-recovery-tests hardlink_v3
STICKIES_DATA_DIR="$TEST_DATA/retry" build/delivery-recovery-tests retry
STICKIES_DATA_DIR="$TEST_DATA/retry" build/delivery-recovery-tests verify_retry
STICKIES_DATA_DIR="$TEST_DATA/corrupt" build/delivery-recovery-tests corrupt
STICKIES_DATA_DIR="$TEST_DATA/future" build/delivery-recovery-tests future
STICKIES_DATA_DIR="$TEST_DATA/crash" build/delivery-recovery-tests hold &
HOLDER_PID=$!
for attempt in {1..100}; do
    [[ -f "$TEST_DATA/crash/ready" ]] && break
    kill -0 "$HOLDER_PID"
    sleep 0.05
done
[[ -f "$TEST_DATA/crash/ready" ]]
STICKIES_DATA_DIR="$TEST_DATA/crash" build/delivery-recovery-tests probe
# Only our isolated test process is killed; no app or real-note process is involved.
kill -KILL "$HOLDER_PID"
wait "$HOLDER_PID" 2>/dev/null || true
HOLDER_PID=""
STICKIES_DATA_DIR="$TEST_DATA/crash" build/delivery-recovery-tests recover
