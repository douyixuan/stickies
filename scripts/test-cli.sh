#!/bin/bash
# End-to-end checks for build/bin/istk against throwaway profiles.
set -euo pipefail
cd "$(dirname "$0")/.."
istk=${ISTK_TEST_BINARY:-build/bin/istk}
if [[ -z ${ISTK_TEST_BINARY:-} && ! -x "$istk" ]]; then
    bash scripts/build-cli.sh >/dev/null
fi
[[ -x "$istk" ]] || { echo "CLI executable missing: $istk" >&2; exit 1; }
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

# Each call is a fresh executable process, never a Store-only substitute.
python3 - "$istk" <<'PY'
import fcntl
import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile
import uuid

cli = str(pathlib.Path(sys.argv[1]).resolve())
assert subprocess.run([cli, 'help'], capture_output=True).returncode == 0
assert json.loads(subprocess.check_output([cli, 'version']))['schemaVersion'] == 10
assert subprocess.run([cli, 'list'], capture_output=True).returncode == 64
assert subprocess.run([cli, '--dir'], capture_output=True).returncode == 64

def run(profile, *args, data=None, code=0):
    result = subprocess.run([cli, '--dir', str(profile), *args], input=data, capture_output=True)
    assert result.returncode == code, (args, result.returncode, result.stderr.decode(errors='replace'))
    return json.loads(result.stdout) if code == 0 else None

def files(profile):
    return {p.name: p.read_bytes() for p in profile.iterdir() if p.is_file()}

with tempfile.TemporaryDirectory() as root:
    root = pathlib.Path(root)
    profile = root / 'Unicode notes 📝'
    text = '中文便签 📝 café\n第二行\n末尾保留\n'
    note = run(profile, 'add', data=text.encode())
    assert note['text'] == text and not note['visible']
    assert run(profile, 'list')['notes'] == [note]
    assert run(profile, 'search', '中文 第二行')['notes'] == [note]
    assert run(profile, 'get', note['id']) == note
    before = files(profile)
    for args in [('list', 'extra'), ('search',), ('search', 'a', 'b'),
                 ('get', 'bad-id'), ('get', note['id'], 'extra'), ('unknown',), ('version', 'extra')]:
        run(profile, *args, code=64)
        assert files(profile) == before
    run(profile, 'add', data=b'\xff\xfe', code=64)
    assert files(profile) == before
    run(profile, 'get', str(uuid.uuid4()), code=66)
    assert files(profile) == before
    absent = root / 'must-not-be-created'
    run(absent, 'list', 'extra', code=64)
    assert not absent.exists()
    print('PASS Unicode/multiline add/list/search/get across fresh processes; invalid input leaves bytes unchanged')

    # The same flock used by the app; no actual app or GUI is started.
    with (profile / 'notes.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        before = files(profile)
        assert run(profile, 'get', note['id']) == note
        run(profile, 'add', 'must not be written', code=69)
        assert files(profile) == before
    print('PASS lock permits reads and rejects writes without changing files')

    # Synthetic shapes from 0.3.105: split content/device state, ledger wrapper,
    # local trash, collapsed layout and preference overrides. Never real profiles.
    for version in (2, 3):
        profile = root / ('legacy-' + str(version))
        profile.mkdir()
        active, trashed = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
        frame = [[-1100, 250], [260, 400]]
        document = {'schemaVersion': 2,
                    'contents': [{'id': active, 'text': text, 'color': 2},
                                 {'id': trashed, 'text': 'synthetic trash', 'color': 1}],
                    'localStates': [{'id': i, 'state': {'frame': frame, 'visible': False}}
                                    for i in (active, trashed)]}
        envelope = document
        if version == 3:
            ledger_profile, request_id = str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()
            segment = json.dumps({'version': 1, 'records': {request_id: {
                'fingerprint': '0' * 64, 'result': {'requestID': request_id, 'notes': []}}}}).encode()
            digest = hashlib.sha256(segment).hexdigest()
            segment_name = 'command-segment-' + ledger_profile + '-' + digest + '.json'
            (profile / segment_name).write_bytes(segment)
            envelope = {'schemaVersion': 3, 'document': document, 'commandLedger': {
                'profile': ledger_profile, 'generation': 1, 'segments': [{
                    'name': segment_name, 'digest': digest, 'size': len(segment), 'count': 1}]}}
        payload = {'notes.json': envelope,
                   'trash.json': {'version': 1, 'ids': [trashed], 'lastBatch': [trashed]},
                   'layout.json': {'schemaVersion': 1, 'collapsed': [active], 'arrangement': 'free'},
                   'preferences.json': {'windowMode': 'desktop', 'keepOnTop': False,
                                        'floatingOverrides': {active: True}, 'snapToScreenEdges': True}}
        for name, value in payload.items():
            (profile / name).write_text(json.dumps(value))
        before = files(profile)
        assert [n['id'] for n in run(profile, 'list')['notes']] == [active]
        assert run(profile, 'get', active)['text'] == text
        run(profile, 'get', trashed, code=66)
        assert all((profile / name).read_bytes() == value for name, value in before.items())
        added = run(profile, 'add', 'new synthetic note')
        assert run(profile, 'get', added['id']) == added
        migrated = json.loads((profile / 'notes.json').read_text())
        assert migrated['schemaVersion'] == 10
        old = {n['id']: n for n in migrated['notes']}
        assert old[active]['text'] == text and old[active]['frame'] == frame
        assert old[active]['color'] == 2 and old[active]['visible'] is False
        assert old[trashed]['text'] == 'synthetic trash'
        assert all((profile / name).read_bytes() == value for name, value in before.items() if name != 'notes.json')
        # A pending old command still blocks the whole CLI, not just writing.
        (profile / 'command-journal.json').write_text('{}')
        before = files(profile)
        run(profile, 'list', code=69)
        run(profile, 'add', 'blocked', code=69)
        assert files(profile) == before
    print('PASS synthetic v2/v3 read-only reads, forward write and reopen, trash/layout preservation, journal refusal')
PY
