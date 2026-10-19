#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/.artifacts.noindex
ICON_STAGE=$(mktemp -d "$PWD/build/.artifacts.noindex/icon.XXXXXX")
trap 'rm -rf "$ICON_STAGE"' EXIT
mkdir "$ICON_STAGE/iStickies2.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Assets/iStickies2.png --out "$ICON_STAGE/iStickies2.iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Assets/iStickies2.png --out "$ICON_STAGE/iStickies2.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
python3 - "$ICON_STAGE/iStickies2.iconset" <<'PYICON'
import pathlib, struct, sys
root = pathlib.Path(sys.argv[1])
representations = [
    (b'icp4', '16x16', 16), (b'icp5', '32x32', 32), (b'icp6', '32x32@2x', 64),
    (b'ic07', '128x128', 128), (b'ic08', '256x256', 256),
    (b'ic09', '512x512', 512), (b'ic10', '512x512@2x', 1024),
    (b'ic11', '16x16@2x', 32), (b'ic12', '32x32@2x', 64),
    (b'ic13', '128x128@2x', 256), (b'ic14', '256x256@2x', 512),
]
chunks = []
for kind, name, size in representations:
    png = (root/('icon_' + name + '.png')).read_bytes()
    assert png[:8] == b'\x89PNG\r\n\x1a\n'
    assert struct.unpack('>II', png[16:24]) == (size, size)
    chunks.append(kind + struct.pack('>I', len(png) + 8) + png)
payload = b''.join(chunks)
pathlib.Path('Assets/iStickies2.icns').write_bytes(b'icns' + struct.pack('>I', len(payload) + 8) + payload)
PYICON
