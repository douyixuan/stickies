"""Exercise command transactions with isolated processes. Never creates NSApplication."""
import hashlib
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import uuid

PROBE = str(Path('build/bin/command-core-probe').resolve())

class CommandCoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='istk-core-')
        self.folder = Path(self.temp.name)
        self.env = dict(os.environ, STICKIES_DATA_DIR=str(self.folder))
    def tearDown(self):
        self.temp.cleanup()
    def request(self, command='add', **fields):
        return dict(id=str(uuid.uuid4()), command=command, ids=[], **fields)
    def call(self, request=None, args=(), code=0):
        p = subprocess.run([PROBE, *args], input=json.dumps(request).encode() if request else b'', env=self.env, capture_output=True, timeout=30)
        self.assertEqual(p.returncode, code, (p.stdout, p.stderr))
        return p.stdout
    def notes(self):
        return json.loads((self.folder/'notes.json').read_text())
    def test_duplicate_add_and_changed_payload(self):
        request = self.request(text='once')
        first = json.loads(self.call(request))
        again = json.loads(self.call(request))
        self.assertEqual(first, again)
        self.assertEqual(len(self.notes()), 1)
        request['text'] = 'different'
        self.call(request, code=74)
        self.assertEqual(self.notes()[0]['text'], 'once')
    def test_process_crash_at_each_commit_stage(self):
        for stage in ['prepared','notesWritten','trashWritten','ledgerWritten','completed']:
            with self.subTest(stage=stage):
                # Each accepted request must recover to one note and its original result.
                request = self.request(text=stage)
                before = len(self.notes()) if (self.folder/'notes.json').exists() else 0
                self.call(request, args=('crash',stage), code=91)
                result = json.loads(self.call(request))
                self.assertEqual(result['notes'][0]['text'], stage)
                self.assertEqual(len(self.notes()), before+1)
                self.assertFalse((self.folder/'command-journal.json').exists())
                self.assertEqual(json.loads(self.call(request)), result)
    def test_precommit_write_failure_has_no_result(self):
        request = self.request(text='not accepted')
        self.folder.chmod(0o500)
        try:
            self.call(request, code=74)
        finally:
            self.folder.chmod(0o700)
        self.assertFalse((self.folder/'command-journal.json').exists())
        self.assertFalse((self.folder/'command-results.json').exists())
        self.call(request)
        self.assertEqual(len(self.notes()),1)
    def test_pending_failure_freezes_mutations(self):
        self.call(self.request(text='before'))
        request = self.request(text='accepted')
        self.assertIn(b'PASS:',self.call(request,args=('freeze','prepared')))
        self.call(request)
        self.assertEqual([n['text'] for n in self.notes()],['before','accepted'])
    def test_recovery_refuses_external_drift(self):
        self.call(self.request(text='before'))
        request = self.request(text='accepted')
        self.call(request,args=('crash','prepared'),code=91)
        notes = self.notes()
        notes[0]['text'] = 'later external change'
        (self.folder/'notes.json').write_text(json.dumps(notes))
        before = (self.folder/'notes.json').read_bytes()
        self.call(request,code=74)
        self.assertEqual((self.folder/'notes.json').read_bytes(),before)
        self.assertTrue((self.folder/'command-journal.json').exists())
    def test_trash_restore_preserves_note_bytes(self):
        result = json.loads(self.call(self.request(text='retained')))
        identity = result['notes'][0]['id']
        before = (self.folder/'notes.json').read_bytes()
        for command in ['delete','restore']:
            request = self.request(command)
            request['ids'] = [identity]
            self.call(request)
            self.assertEqual((self.folder/'notes.json').read_bytes(),before)
    def test_parallel_main_actor_requests(self):
        self.assertEqual(self.call(args=('parallel',)).strip(), b'20')
        self.assertEqual(len(self.notes()),20)
    def test_live_reads_keep_unsaved_edits(self):
        self.assertIn(b'PASS:',self.call(args=('unsaved',)))
    def test_reentrant_publication_rejects_nested_commands(self):
        self.call(self.request(text='outer'),args=('reentrant',))
        self.assertEqual([n['text'] for n in self.notes()],['outer'])
    def test_restore_keeps_newer_sync_content(self):
        result = json.loads(self.call(self.request(text='old')))
        identity = result['notes'][0]['id']
        delete = self.request('delete')
        delete['ids'] = [identity]
        self.call(delete)
        self.call(self.request(text='new synchronized text'),args=('sync',))
        restore = self.request('restore')
        restore['ids'] = [identity]
        self.call(restore)
        self.assertEqual(self.notes()[0]['text'],'new synchronized text')
        # Replaying an older accepted deletion cannot delete a restored note again.
        self.call(delete)
        self.assertEqual(json.loads((self.folder/'trash.json').read_text())['ids'],[])
    def test_capacity_does_not_evict_old_request_results(self):
        request = self.request(text='old request')
        result = json.loads(self.call(request))
        path = self.folder/'command-results.json'
        ledger = json.loads(path.read_text())
        for _ in range(4095):
            identity = str(uuid.uuid4()).upper()
            ledger['records'][identity] = dict(fingerprint='0'*64,result=dict(requestID=identity,notes=[]))
        path.write_text(json.dumps(ledger))
        before = path.read_bytes()
        self.assertEqual(json.loads(self.call(request)),result)
        self.call(self.request(text='over capacity'),code=74)
        self.assertEqual(path.read_bytes(),before)
        self.assertEqual(len(self.notes()),1)
    def test_core_requires_note_store_lock_ownership(self):
        self.call(self.request(text='original'))
        before = (self.folder/'notes.json').read_bytes()
        with (self.folder/'notes.lock').open('rb') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            self.call(self.request(text='must fail'),code=74)
        self.assertEqual((self.folder/'notes.json').read_bytes(),before)
    def test_completed_observation_failure_keeps_committed_result(self):
        request = self.request(text='committed')
        result = json.loads(self.call(request,args=('freeze','completed')))
        self.assertEqual(result['notes'][0]['text'],'committed')
        self.assertEqual(json.loads(self.call(request)),result)
    def test_offline_cli_recovers_before_writing(self):
        request = self.request(text='accepted by app')
        self.call(request,args=('crash','notesWritten'),code=91)
        cli = str(Path('build/bin/istk').resolve())
        result = subprocess.run([cli,'add','--text','later offline command'],env=self.env,capture_output=True,timeout=10)
        self.assertEqual(result.returncode,0,result.stderr)
        self.call(request)
        self.assertEqual([n['text'] for n in self.notes()],['accepted by app','later offline command'])

if __name__ == '__main__':
    unittest.main()
