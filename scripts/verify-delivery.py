"""Verify archived metadata, executable, icon and signature without launching/registering."""
import hashlib
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import zipfile

if not __debug__:
    sys.exit("Run archive verification without Python optimization")

with zipfile.ZipFile(sys.argv[1]) as archive:
    names = archive.namelist()
    assert len(names) == len(set(names)), 'Duplicate archive entries'
    roots = {n.split('/')[0] for n in names}
    assert len(roots) == 1
    root = next(iter(roots)) + '/'
    app = root + 'iStickies2.app/'
    assert {root + 'START-HERE.txt', root + 'SYNC.md', root + 'SHA256SUMS.txt'}.issubset(names)
    assert archive.read(root + 'SYNC.md').decode('utf-8').strip(), 'Missing sync instructions'
    assert all(n.startswith(app) or n in {root + 'START-HERE.txt', root + 'SYNC.md', root + 'SHA256SUMS.txt'} for n in names)
    assert not any('.app/' in n[len(app):] for n in names if n.startswith(app))
    info = plistlib.loads(archive.read(app + 'Contents/Info.plist'))
    assert info['CFBundleName'] == info['CFBundleDisplayName'] == 'iStickies2'
    assert info['CFBundleIdentifier'] == 'dev.douyixuan.stickies.delivery'
    assert info['CFBundleIconFile'] == 'iStickies2.icns'
    assert 'LSEnvironment' not in info  # no developer's private data path in public packages
    icon = archive.read(app + 'Contents/Resources/iStickies2.icns')
    assert icon[:4] == b'icns' and struct.unpack('>I', icon[4:8])[0] == len(icon)
    expected_sizes = {b'icp4':16, b'icp5':32, b'icp6':64, b'ic07':128, b'ic08':256, b'ic09':512, b'ic10':1024, b'ic11':32, b'ic12':64, b'ic13':256, b'ic14':512}
    types = set()
    offset = 8
    while offset < len(icon):
        kind, length = struct.unpack('>4sI', icon[offset:offset+8])
        assert length >= 8 and offset + length <= len(icon)
        assert kind not in types and kind in expected_sizes
        png = icon[offset+8:offset+length]
        assert png[:8] == b'\x89PNG\r\n\x1a\n'
        assert struct.unpack('>II', png[16:24]) == (expected_sizes[kind],) * 2
        types.add(kind); offset += length
    assert offset == len(icon) and {b'ic07', b'ic08', b'ic09', b'ic10'}.issubset(types)
    manifest_files = set()
    for line in archive.read(root + 'SHA256SUMS.txt').decode().splitlines():
        checksum, relative = line.split('  ', 1)
        assert relative not in manifest_files
        manifest_files.add(relative)
        assert hashlib.sha256(archive.read(root + relative)).hexdigest() == checksum
    assert manifest_files == {n[len(root):] for n in names if n != root + 'SHA256SUMS.txt'}
    executable = archive.getinfo(app + 'Contents/MacOS/' + info['CFBundleExecutable'])
    assert (executable.external_attr >> 16) & 0o111
    # Extract under a non-app name; verification never opens or registers an application.
    with tempfile.TemporaryDirectory(prefix='istickies2-verify-') as directory:
        payload = Path(directory) / 'payload'
        for entry in archive.infolist():
            if not entry.filename.startswith(app) or entry.is_dir():
                continue
            relative = Path(entry.filename[len(app):])
            assert not relative.is_absolute() and '..' not in relative.parts
            target = payload / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))
            target.chmod((entry.external_attr >> 16) & 0o777)
        subprocess.run(['codesign', '--verify', '--deep', '--strict', str(payload)], check=True)
        checker = payload/'Contents/MacOS/NoteDataCheck'
        assert checker.is_file() and checker.stat().st_mode & 0o111
        assert set(subprocess.check_output(['lipo', '-archs', str(checker)], text=True).split()) == {'arm64', 'x86_64'}
        fixture = Path(directory)/'notes.json'
        fixture.write_text('{"schemaVersion":2,"contents":[],"localStates":[],"future":{"preserved":true}}')
        before = fixture.read_bytes()
        subprocess.run([str(checker), str(fixture)], check=True)
        assert fixture.read_bytes() == before and not (fixture.parent/'notes.lock').exists()
        fixture.write_text('{"schemaVersion":999}')
        assert subprocess.run([str(checker), str(fixture)]).returncode != 0
        architectures = subprocess.check_output(['lipo', '-archs', str(payload/'Contents/MacOS'/info['CFBundleExecutable'])], text=True).split()
        assert set(architectures) == {'arm64', 'x86_64'}
print('PASS: one iStickies2 app, stable identity, icon sizes, all hashes, executable mode, universal signature')
