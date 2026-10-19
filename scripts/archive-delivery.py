"""Archive a staging payload as iStickies2.app without creating an on-disk .app."""
import hashlib
from pathlib import Path
import sys
import zipfile

package, destination, name = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
entries = [(p, 'iStickies2.app/' + p.relative_to(package / 'payload').as_posix())
           for p in sorted((package / 'payload').rglob('*')) if p.is_file()]
entries.append((package / 'START-HERE.txt', 'START-HERE.txt'))
checksums = ''.join(f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {relative}\n' for p, relative in entries)
# Exclusive creation protects previous releases. Preserve Unix executable modes via write().
with zipfile.ZipFile(destination, 'x', compression=zipfile.ZIP_DEFLATED) as archive:
    for path, relative in entries:
        archive.write(path, name + '/' + relative)
    archive.writestr(name + '/SHA256SUMS.txt', checksums)
print('Archived one user-facing iStickies2.app; staging has no .app suffix')
