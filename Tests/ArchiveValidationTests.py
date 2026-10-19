"""Negative tests against a real signed release ZIP; never launches an app."""
from pathlib import Path
import subprocess
import sys
import tempfile
import zipfile

source = Path(sys.argv[1])
with zipfile.ZipFile(source) as archive:
    originals = [(i, archive.read(i)) for i in archive.infolist()]
root = originals[0][0].filename.split('/')[0] + '/'
with tempfile.TemporaryDirectory(prefix='istickies2-archive-tests-') as directory:
    for case in ['empty_manifest', 'extra_app', 'duplicate_path', 'missing_icon', 'corrupt_icon', 'missing_sync_guide']:
        target = Path(directory)/(case + '.zip')
        with zipfile.ZipFile(target, 'w') as output:
            for info, content in originals:
                if case == 'missing_sync_guide' and info.filename.endswith('SYNC.md'):
                    continue
                if case == 'missing_sync_guide' and info.filename.endswith('SHA256SUMS.txt'):
                    content = b'\n'.join(line for line in content.splitlines() if not line.endswith(b'  SYNC.md')) + b'\n'
                if case == 'missing_icon' and info.filename.endswith('.icns'):
                    continue
                if case == 'empty_manifest' and info.filename.endswith('SHA256SUMS.txt'):
                    content = b''
                if case == 'corrupt_icon' and info.filename.endswith('.icns'):
                    content = b'not an icon'
                output.writestr(info, content)
            if case == 'extra_app':
                output.writestr(root + 'Other.app/Contents/Info.plist', b'extra')
            if case == 'duplicate_path':
                output.writestr(originals[0][0], originals[0][1])
        result = subprocess.run([sys.executable, 'scripts/verify-delivery.py', str(target)], capture_output=True)
        assert result.returncode != 0, f'Incorrectly accepted {case}'
        print('PASS: rejected', case)
