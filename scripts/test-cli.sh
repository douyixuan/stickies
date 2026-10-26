#!/bin/bash
# End-to-end checks for build/bin/istk against throwaway profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -x build/bin/istk ]] || bash scripts/build-cli.sh >/dev/null
istk=build/bin/istk
dir=$(mktemp -d)
trap 'rm -rf "$dir"' EXIT

"$istk" --dir "$dir" add "Call Ana about the invoice" >/dev/null
found=$("$istk" --dir "$dir" search "ana invoice")
grep -q '"Call Ana about the invoice"' <<<"$found"
echo "PASS add, then search finds the note"

printf 'not a trash file' > "$dir/trash.json"
if "$istk" --dir "$dir" list >/dev/null 2>&1; then
    echo "FAIL list succeeded on a profile it could not fully read" >&2
    exit 1
fi
echo "PASS an unreadable profile fails instead of answering"
