"""Capture build inputs once; both compilers consume only this private snapshot."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

INPUTS = ('Stickies', 'Tools', 'Assets', 'scripts', 'project.yml')

def capture(root, destination):
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip()
    expected = {}
    entries = subprocess.check_output(['git', 'ls-tree', '-rz', source, '--', *INPUTS], cwd=root)
    for entry in entries.split(b'\0'):
        if not entry:
            continue
        meta, name = entry.split(b'\t', 1)
        mode, kind, oid = meta.split()
        if kind != b'blob' or mode not in (b'100644', b'100755'):
            raise ValueError('Unsupported build input: ' + os.fsdecode(name))
        expected[os.fsdecode(name)] = (mode == b'100755', subprocess.check_output(['git', 'cat-file', 'blob', oid.decode()], cwd=root))
    captured = {}
    for name in INPUTS:
        base = root / name
        paths = base.rglob('*') if base.is_dir() else [base]
        for path in sorted(paths):
            if '__pycache__' in path.parts or path.suffix == '.pyc':
                continue
            if path.is_symlink():
                raise ValueError('Symlink build input is not isolated: ' + str(path))
            if not path.is_file():
                continue
            rel = path.relative_to(root).as_posix()
            # Read once. Provenance is computed from these bytes, never a later live read.
            value = (bool(path.stat().st_mode & 0o111), path.read_bytes())
            captured[rel] = value
            target = destination / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(value[1])
            target.chmod(0o555 if value[0] else 0o444)
    digest = hashlib.sha256()
    for name, (executable, data) in sorted(captured.items()):
        digest.update(json.dumps([name, executable, hashlib.sha256(data).hexdigest()]).encode())
    provenance = dict(sourceSHA=source, clean=captured == expected, inputSHA256=digest.hexdigest())
    (destination / 'build-inputs.json').write_text(json.dumps(provenance))
    (destination / 'build-inputs.json').chmod(0o444)
    return provenance

def main():
    root = Path(__file__).resolve().parent.parent
    with tempfile.TemporaryDirectory(prefix='istk build snapshot ') as folder:
        snapshot = Path(folder)
        capture(root, snapshot)
        subprocess.run(['bash', str(snapshot / 'scripts/build-app-inner.sh')], cwd=snapshot, check=True)
        result = root / 'build/iStickies2.app'
        result.parent.mkdir(exist_ok=True)
        if result.exists():
            shutil.rmtree(result)
        shutil.copytree(snapshot / 'build/iStickies2.app', result, symlinks=True)
    print('Built development candidate at ' + str(result))

if __name__ == '__main__':
    main()
