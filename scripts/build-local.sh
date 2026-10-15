#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/Stickies.app"
mkdir -p "$APP/Contents/MacOS" build/module-cache
xcrun swiftc -module-cache-path "$PWD/build/module-cache" -parse-as-library -target "$(uname -m)-apple-macosx14.0" Stickies/*.swift -o "$APP/Contents/MacOS/StickiesPreview"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>StickiesPreview</string>
<key>CFBundleIdentifier</key><string>dev.douyixuan.stickies.local-preview</string>
<key>CFBundleName</key><string>Stickies Preview</string>
<key>CFBundleDisplayName</key><string>Stickies Preview</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
printf 'Built %s\n' "$APP"
