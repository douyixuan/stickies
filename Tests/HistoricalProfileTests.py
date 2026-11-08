#!/usr/bin/env python3
"""Run the actual CLI against public-history writer fixtures in throwaway profiles.
Adds historical provenance and complete backup/upgrade/restore coverage; existing
Store/CLI suites own generic corrupt/future-schema, lock and write-failure checks.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / 'Tests/Fixtures/HistoricalProfiles'
CLI = str(Path(sys.argv[1]).resolve())
BACKUP = ROOT / 'scripts/profile-backup.py'


def files(directory):
    return {p.relative_to(directory).as_posix(): p.read_bytes()
            for p in directory.rglob('*') if p.is_file() and p.name != 'notes.lock'}


def run(profile, *args, code=0):
    result = subprocess.run([CLI, '--dir', str(profile), *args], capture_output=True)
    assert result.returncode == code, (args, result.returncode, result.stderr.decode())
    return json.loads(result.stdout) if code == 0 else None


def projected(value):
    if isinstance(value, list):
        return value
    if value['schemaVersion'] == 3:
        return projected(value['document'])
    assert value['schemaVersion'] == 2
    states = {entry['id']: entry['state'] for entry in value['localStates']}
    return [dict(content, **states[content['id']]) for content in value['contents']]


def backup_command(*args):
    result = subprocess.check_output([sys.executable, str(BACKUP), *map(str, args)])
    assert json.loads(result)['status'] == 'verified'


provenance = json.loads((FIXTURES / 'provenance.json').read_text())
for name, expected in provenance['fixtureSHA256'].items():
    assert hashlib.sha256((FIXTURES / name).read_bytes()).hexdigest() == expected, name
actual_names = {str(p.relative_to(FIXTURES)) for p in FIXTURES.rglob('*')
                if p.is_file() and p.name != 'provenance.json'}
assert actual_names == set(provenance['fixtureSHA256'])

with tempfile.TemporaryDirectory(prefix='istk historical acceptance ') as temporary:
    root = Path(temporary)
    for version in ('v01', 'v02', 'v03'):
        profile = root / version
        shutil.copytree(FIXTURES / version, profile)
        original = files(profile)
        expected = projected(json.loads(original['notes.json']))
        listed = run(profile, 'list')['notes']
        assert {note['id'] for note in listed} == {note['id'] for note in expected}
        for note in expected:
            loaded = run(profile, 'get', note['id'])
            assert all(loaded[k] == note[k] for k in ('id', 'text', 'color', 'visible'))
        assert files(profile) == original, 'Read-only load must retain original bytes'
        archive = root / (version + '.zip')
        backup_command('backup', profile, archive)
        backup_command('verify', archive)
        added = run(profile, 'add', 'New synthetic edit after historical upgrade')
        assert run(profile, 'get', added['id']) == added
        upgraded = json.loads((profile / 'notes.json').read_bytes())
        assert upgraded['schemaVersion'] == 10
        stored = {note['id']: note for note in upgraded['notes']}
        for note in expected:
            assert all(stored[note['id']][key] == value for key, value in note.items())
        assert {k: v for k, v in files(profile).items() if k != 'notes.json'} == {
            k: v for k, v in original.items() if k != 'notes.json'}
        restored = root / (version + '-restored')
        backup_command('restore', archive, restored)
        assert files(restored) == original, 'Whole-profile rollback must be byte-exact'
        assert run(restored, 'list')['notes'] == listed
        assert files(restored) == original
        assert run(profile, 'get', added['id']) == added, 'Newer edits remain in the upgraded profile'
    pending = root / 'journal'
    shutil.copytree(FIXTURES / 'v03-journal', pending)
    before = files(pending)
    run(pending, 'list', code=69)
    run(pending, 'add', 'must not overwrite a prepared historical command', code=69)
    assert files(pending) == before
    backup_command('backup', pending, root / 'journal.zip')
    backup_command('restore', root / 'journal.zip', root / 'journal-restored')
    assert files(root / 'journal-restored') == before
print('PASS historical-writer v01/v02/v03 CLI upgrade, byte-exact full rollback, retained newer edits and genuine prepared journal refusal')
