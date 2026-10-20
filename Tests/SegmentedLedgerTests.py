"""Temporary profiles only; no app or GUI launch."""
import base64, fcntl, hashlib, json, os, subprocess, tempfile, unittest, uuid
from pathlib import Path
CLI = str(Path('build/bin/istk').resolve())
PROBE = str(Path('build/bin/segmented-ledger-probe').resolve())
OLD = str(Path('build/bin/istk-before-segments').resolve())
class SegmentedLedgerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='istk-ledger-')
        self.path = Path(self.temp.name)
        self.call('add', '--text', 'original')
    def tearDown(self): self.temp.cleanup()
    def call(self, *args, code=0, binary=CLI):
        p = subprocess.run([binary, '--data-dir', str(self.path), *args], capture_output=True)
        self.assertEqual(p.returncode, code, (p.stdout, p.stderr))
        return json.loads(p.stdout) if code == 0 else None
    def snapshot(self):
        return {p.name:p.read_bytes() for p in self.path.iterdir() if p.is_file() and p.name != 'notes.lock'}
    def test_old_writer_gate(self):
        self.call('migrate-ledger')
        before = self.snapshot()
        self.call('add', '--text', 'old must refuse', binary=OLD, code=65)
        self.assertEqual(before, self.snapshot())
    def test_exact_old_app_and_cli_writers(self):
        self.call('migrate-ledger')
        for revision in ['c199a7a335c6d2e7f5b076e431efc23b7b101a6a','fe5bf47e992e57fa7483f61645ba56f4d988cdac','74aec5511cb6d855913ba0a8f733f2a39f3a2978']:
            before = self.snapshot()
            binary = Path('build/bin/old-writer-'+revision).resolve()
            p = subprocess.run([str(binary)],env=dict(os.environ,STICKIES_DATA_DIR=str(self.path)),capture_output=True)
            self.assertEqual(p.returncode,0,p.stderr)
            self.assertEqual(before,self.snapshot())
            old_cli = Path('build/bin/old-cli-'+revision).resolve()
            if revision != 'c199a7a335c6d2e7f5b076e431efc23b7b101a6a':
                self.call('add','--text','blocked',binary=str(old_cli),code=65)
                self.assertEqual(before,self.snapshot())
    def test_single_publication_and_repeat(self):
        legacy = (self.path/'command-results.json').read_bytes()
        self.call('migrate-ledger')
        wrapper = json.loads((self.path/'notes.json').read_bytes())
        self.assertEqual(wrapper['schemaVersion'], 3)
        self.assertEqual(wrapper['document'][0]['text'], 'original')
        self.assertEqual(wrapper['commandLedger']['generation'], 0)
        self.assertEqual(legacy, (self.path/'command-results.json').read_bytes())
        before = self.snapshot()
        self.call('migrate-ledger')
        self.assertEqual(before, self.snapshot())
    def test_old_journal_cannot_cross_gate(self):
        before_notes = (self.path/'notes.json').read_bytes()
        legacy = (self.path/'command-results.json').read_bytes()
        trash = (self.path/'trash.json').read_bytes()
        self.call('migrate-ledger')
        current = (self.path/'notes.json').read_bytes()
        enc = lambda b:base64.b64encode(b).decode()
        journal = dict(version=1, notes=enc(before_notes), trash=enc(trash), ledger=enc(legacy),
                       previousNotes=hashlib.sha256(current).hexdigest(),
                       previousTrash=hashlib.sha256(trash).hexdigest(), previousLedger=hashlib.sha256(legacy).hexdigest())
        (self.path/'command-journal.json').write_text(json.dumps(journal))
        before = self.snapshot()
        self.call('add', '--text', 'blocked', code=65)
        self.assertEqual(before, self.snapshot())
    def test_generation_mismatch_rejected_before_writes(self):
        self.call('migrate-ledger')
        notes = (self.path/'notes.json').read_bytes()
        wrapper = json.loads(notes)
        manifest = wrapper['commandLedger']
        wrapper['commandLedger']['generation'] += 2
        trash = (self.path/'trash.json').read_bytes()
        enc = lambda b:base64.b64encode(b).decode()
        journal = dict(version=2, notes=enc(json.dumps(wrapper).encode()), trash=enc(trash), ledger=enc(b''),
                       previousNotes=hashlib.sha256(notes).hexdigest(), previousTrash=hashlib.sha256(trash).hexdigest(),
                       profile=manifest['profile'], generation=0, previousManifest=json.loads(notes)['commandLedger'])
        (self.path/'command-journal.json').write_text(json.dumps(journal))
        before = self.snapshot()
        self.call('list', code=65)
        self.assertEqual(before, self.snapshot())
    def crash(self, command, stage, request=None):
        p = subprocess.run([PROBE, str(self.path), command, stage], input=json.dumps(request).encode() if request else b'', capture_output=True)
        self.assertEqual(p.returncode, 91, p.stderr)
    def test_migration_crash_publication(self):
        old = (self.path/'notes.json').read_bytes()
        self.crash('migrate', 'staged')
        self.assertEqual(old, (self.path/'notes.json').read_bytes())
        self.call('list', binary=OLD)
        self.crash('migrate', 'published')
        self.assertEqual(json.loads((self.path/'notes.json').read_bytes())['schemaVersion'], 3)
        self.call('list')
        self.call('migrate-ledger')
    def test_all_command_crash_stages(self):
        self.call('migrate-ledger')
        for stage in ['prepared','notesWritten','trashWritten','ledgerWritten','completed']:
            identity = str(uuid.uuid4()).upper()
            request = dict(id=identity, command='add', ids=[], text=stage, visibleOnCreate=True)
            self.crash('command', stage, request)
            first = self.call('result', identity)['data']
            again = self.call('add','--text',stage,'--request-id',identity)['data']
            self.assertEqual(first['notes'][0]['id'], again['id'])
            self.assertFalse((self.path/'command-journal.json').exists())
        self.assertEqual(len(self.call('list')['data']), 6)
    def test_capacity_history_and_conflict(self):
        ledger_path = self.path/'command-results.json'
        ledger = json.loads(ledger_path.read_bytes())
        original_id, original_record = next(iter(ledger['records'].items()))
        for i in range(4095):
            identity = str(uuid.uuid4()).upper()
            ledger['records'][identity] = dict(fingerprint='a'*64, result=dict(requestID=identity, notes=[]))
        ledger_path.write_text(json.dumps(ledger))
        self.call('add','--text','full',code=75)
        self.call('migrate-ledger')
        for i in range(6): self.call('add','--text',str(i))
        self.assertEqual(self.call('result',original_id)['data'], original_record['result'])
        self.call('add','--text','conflict','--request-id',original_id,code=64)
        manifest = json.loads((self.path/'notes.json').read_bytes())['commandLedger']
        self.assertEqual(sum(s['count'] for s in manifest['segments']),4102)
        all_records = {}
        for segment in manifest['segments']:
            all_records.update(json.loads((self.path/segment['name']).read_bytes())['records'])
        for identity, record in ledger['records'].items(): self.assertEqual(all_records[identity], record)
    def test_missing_and_corrupt_segment_preserve_files(self):
        self.call('migrate-ledger')
        manifest = json.loads((self.path/'notes.json').read_bytes())['commandLedger']
        segment = self.path/manifest['segments'][0]['name']
        data = segment.read_bytes()
        segment.unlink()
        before = self.snapshot()
        self.call('add','--text','blocked',code=65)
        self.assertEqual(before,self.snapshot())
        segment.write_bytes(data+b' ')
        before = self.snapshot()
        self.call('add','--text','blocked',code=65)
        self.assertEqual(before,self.snapshot())
    def test_locked_migration_never_routes_live(self):
        with (self.path/'notes.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            before = self.snapshot()
            self.call('migrate-ledger',code=75)
            self.assertEqual(before,self.snapshot())
    def test_read_only_directory_preserves_legacy(self):
        before = self.snapshot()
        self.path.chmod(0o500)
        try: self.call('migrate-ledger',code=74)
        finally: self.path.chmod(0o700)
        self.assertEqual(before,self.snapshot())
    def test_pending_journal_io_is_74_and_preserves_bytes(self):
        self.call('migrate-ledger')
        request = dict(id=str(uuid.uuid4()).upper(),command='add',ids=[],text='pending')
        self.crash('command','prepared',request)
        before = self.snapshot()
        manifest = json.loads((self.path/'notes.json').read_bytes())['commandLedger']
        for path in [self.path/'notes.json', self.path/manifest['segments'][0]['name']]:
            path.chmod(0)
            try: self.call('list',code=74)
            finally: path.chmod(0o600)
            self.assertEqual(before,self.snapshot())
        self.call('list')
    def test_pending_generation_and_profile_tampering(self):
        self.call('migrate-ledger')
        request = dict(id=str(uuid.uuid4()).upper(),command='add',ids=[],text='pending')
        self.crash('command','prepared',request)
        path = self.path/'command-journal.json'
        original = path.read_bytes()
        for field, value in [('profile',str(uuid.uuid4())),('generation',2)]:
            journal = json.loads(original)
            journal[field] = value
            path.write_text(json.dumps(journal))
            before = self.snapshot()
            self.call('list',code=65)
            self.assertEqual(before,self.snapshot())
        path.write_bytes(original)
        self.call('list')
    def test_migration_recovers_previous_transaction_first(self):
        request = dict(id=str(uuid.uuid4()).upper(),command='add',ids=[],text='accepted before migration')
        self.crash('command','prepared',request)
        self.call('migrate-ledger')
        self.assertEqual(self.call('result',request['id'])['data']['notes'][0]['text'],request['text'])
        self.assertFalse((self.path/'command-journal.json').exists())
    def test_invalid_manifest_and_segment_links(self):
        self.call('migrate-ledger')
        path = self.path/'notes.json'
        original = path.read_bytes()
        for mutation in ['duplicate','path','size','malformed']:
            wrapper = json.loads(original)
            segments = wrapper['commandLedger']['segments']
            if mutation == 'duplicate': segments.append(segments[0].copy())
            if mutation == 'path': segments[0]['name'] = '../outside.json'
            if mutation == 'size': segments[0]['size'] += 1
            if mutation == 'malformed': wrapper['commandLedger']['generation'] = 'invalid'
            path.write_text(json.dumps(wrapper))
            before = self.snapshot()
            self.call('add','--text','blocked',code=65)
            self.assertEqual(before,self.snapshot())
        path.write_bytes(original)
        segment = self.path/json.loads(original)['commandLedger']['segments'][0]['name']
        data = segment.read_bytes()
        segment.unlink()
        target = self.path/'separate.json'; target.write_bytes(data)
        segment.symlink_to(target)
        before = self.snapshot()
        self.call('list',code=65)
        self.assertEqual(before,self.snapshot())
    def test_app_edits_sync_and_damaged_inventory(self):
        self.call('migrate-ledger')
        original = json.loads((self.path/'notes.json').read_bytes())
        for mode in ['edit','damage']:
            p = subprocess.run([str(Path('build/bin/segmented-app-probe').resolve()),mode],env=dict(os.environ,STICKIES_DATA_DIR=str(self.path)),capture_output=True)
            self.assertEqual(p.returncode,0,p.stderr)
            wrapper = json.loads((self.path/'notes.json').read_bytes())
            self.assertEqual(wrapper['commandLedger'],original['commandLedger'])
            if mode == 'edit':
                self.assertEqual(wrapper['document'][0]['text'],'remote edit')
                (self.path/'preferences.json').unlink()
    def test_injected_out_of_space_before_publication(self):
        notes = (self.path/'notes.json').read_bytes()
        ledger = (self.path/'command-results.json').read_bytes()
        p = subprocess.run([PROBE,str(self.path),'no-space'],capture_output=True)
        self.assertEqual(p.returncode,74,p.stderr)
        self.assertEqual(notes,(self.path/'notes.json').read_bytes())
        self.assertEqual(ledger,(self.path/'command-results.json').read_bytes())
        self.call('migrate-ledger')
    def test_lossless_document_survives_migration_and_edit(self):
        path = self.path/'notes.json'
        notes = json.loads(path.read_bytes())
        identity = notes[0]['id']
        notes[0]['future'] = '__TOKEN__'
        token = '1234567890123456789012345678901234567890.123456789'
        path.write_text(json.dumps(notes).replace('"__TOKEN__"',token))
        self.call('migrate-ledger')
        self.call('edit',identity,'--text','changed')
        self.assertIn(token,path.read_text())
    def test_matching_hash_invalid_segment_json_is_data_error(self):
        self.call('migrate-ledger')
        path = self.path/'notes.json'
        original = path.read_bytes()
        for data in [b'{bad json',b'{"version":1,"version":1,"records":{}}']:
            wrapper = json.loads(original)
            manifest = wrapper['commandLedger']
            digest = hashlib.sha256(data).hexdigest()
            name = 'command-segment-'+manifest['profile']+'-'+digest+'.json'
            (self.path/name).write_bytes(data)
            manifest['segments'][0].update(name=name,digest=digest,size=len(data))
            path.write_text(json.dumps(wrapper))
            before = self.snapshot()
            self.call('list',code=65)
            self.assertEqual(before,self.snapshot())
if __name__ == '__main__': unittest.main()
