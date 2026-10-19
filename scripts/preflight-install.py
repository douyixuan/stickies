"""Read-only gate. Run against the staged candidate before replacing an app."""
import hashlib
from pathlib import Path
import subprocess
import sys

candidate, notes = map(Path, sys.argv[1:])
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(candidate)], check=True)
checker = candidate / 'Contents/MacOS/NoteDataCheck'
assert checker.is_file(), 'Candidate has no compatibility checker; stop installation'
before = hashlib.sha256(notes.read_bytes()).digest()
subprocess.run([str(checker), str(notes)], check=True)
assert hashlib.sha256(notes.read_bytes()).digest() == before, 'Data changed during preflight; retry with a fresh snapshot'
print('PASS: signed candidate pre-install compatibility gate; no app launched')
