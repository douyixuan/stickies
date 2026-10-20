"""CLI integration with temporary fixtures only. Never starts an app or cloud transport."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest
import uuid

CLI = Path(os.environ.get('ISTK_TEST_BINARY', 'build/bin/istk')).resolve()

class CLIIntegration(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='istk-cli-')
        self.folder = Path(self.temp.name) / 'profile'
        self.env = dict(os.environ)
        self.env.pop('STICKIES_DATA_DIR', None)
    def tearDown(self):
        self.temp.cleanup()
    def call(self, *args, code=0, stdin=None):
        p = subprocess.run([str(CLI), '--data-dir', str(self.folder), *args], input=stdin, capture_output=True, env=self.env)
        self.assertEqual(p.returncode, code, (p.returncode, p.stdout, p.stderr))
        result = json.loads(p.stdout if code == 0 else p.stderr)
        self.assertEqual(result['schemaVersion'], 1)
        self.assertEqual(result['ok'], code == 0)
        self.assertEqual(p.stderr if code == 0 else p.stdout, b'')
        return result.get('data') if code == 0 else result['error']
    def hashes(self):
        return {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in self.folder.iterdir() if p.name != 'notes.lock' and p.is_file()}
    def add(self, text='test'):
        return self.call('add', '--text', text)['id']
    def test_help_version_no_profile(self):
        self.assertIn('delete', self.call('help')['commands'])
        self.assertEqual(self.call('version')['name'], 'istk')
        self.assertFalse(self.folder.exists())
        p = subprocess.run([str(CLI), 'list'], capture_output=True, env=self.env)
        self.assertEqual(p.returncode, 64)
        self.assertEqual(json.loads(p.stderr)['error']['code'], 'usage')
    def test_crud_search_stdin_and_restore(self):
        text = 'Unicode 工作\nCafé\n' + ('chunk\n' * 30000)
        first = self.call('add', '--stdin', '--color', '2', stdin=text.encode())
        second = self.add('Other note')
        self.assertEqual(first['text'], text)
        self.assertEqual(len(self.call('search', 'cafe 工作')), 1)
        self.assertEqual(self.call('get', first['id'])['color'], 2)
        self.call('edit', first['id'], '--stdin', stdin=b'updated\n')
        before = (self.folder / 'notes.json').read_bytes()
        result = self.call('delete', first['id'], second)
        self.assertEqual(result['count'], 2)
        self.assertEqual(result['scope'], 'this_mac')
        self.assertEqual(self.call('list'), [])
        self.assertEqual(len(self.call('list', '--trash')), 2)
        self.assertEqual(self.call('get', first['id'], '--trash')['text'], 'updated\n')
        self.call('edit', first['id'], '--text', 'must not edit trash', code=66)
        self.call('restore', first['id'], second)
        self.assertEqual(len(self.call('list')), 2)
        self.assertEqual((self.folder / 'notes.json').read_bytes(), before)
    def test_rejects_invalid_batch_without_partial_change(self):
        first = self.add()
        before = self.hashes()
        self.call('delete', first, str(uuid.uuid4()), code=66)
        self.assertEqual(self.hashes(), before)
        self.call('delete', first, first, code=64)
        self.assertEqual(self.hashes(), before)
        self.call('edit', first, '--color', '8', code=64)
        self.assertEqual(self.hashes(), before)
    def test_lock_blocks_reads_and_writes(self):
        first = self.add()
        before = self.hashes()
        with (self.folder / 'notes.lock').open('rb') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for args in [('list',), ('get', first), ('search', 'test'), ('add',), ('edit', first, '--text', 'x'), ('delete', first), ('restore', first)]:
                self.assertEqual(self.call(*args, code=75)['code'], 'locked')
        self.assertEqual(self.hashes(), before)
        self.call('get', first)
    def test_v2_extensions_and_legacy_preserved(self):
        for v2 in [False, True]:
            self.folder.mkdir(exist_ok=True)
            identity = str(uuid.uuid4()).upper()
            note = {'id': identity, 'text': 'original', 'color': 1, 'frame': [[22, 33], [260, 220]], 'visible': False, 'extension': {'value': 'retained'}}
            value = {'schemaVersion': 2, 'contents': [{k:v for k,v in note.items() if k in ['id', 'text', 'color', 'extension']}], 'localStates': [{'id':identity,'localExtension':'keep','state':{'frame': note['frame'],'visible':False,'stateExtension':'keep'}}], 'rootExtension':'keep'} if v2 else [note]
            (self.folder/'notes.json').write_text(json.dumps(value))
            self.call('edit', identity, '--text', 'new')
            actual = json.loads((self.folder/'notes.json').read_text())
            if v2:
                self.assertEqual(actual['rootExtension'], 'keep')
                self.assertEqual(actual['localStates'], value['localStates'])
                self.assertEqual(actual['contents'][0]['extension'], note['extension'])
            else:
                self.assertEqual(actual[0]['extension'], note['extension'])
                self.assertEqual(actual[0]['frame'], note['frame'])
                self.assertFalse(actual[0]['visible'])
            self.call('delete', identity)
            self.call('restore', identity)
            self.assertEqual(json.loads((self.folder/'notes.json').read_text()), actual)
    def test_failed_writes_and_invalid_data_do_not_report_success(self):
        first = self.add()
        notes = (self.folder/'notes.json').read_bytes()
        (self.folder/'trash.json').mkdir()
        self.call('delete', first, code=65)
        self.assertEqual((self.folder/'notes.json').read_bytes(), notes)
        (self.folder/'trash.json').rmdir()
        (self.folder/'trash.json').write_text('{"version":999,"ids":[],"lastBatch":[]}')
        self.call('add', code=65)
        self.assertEqual((self.folder/'notes.json').read_bytes(), notes)
        (self.folder/'trash.json').unlink()
        (self.folder/'notes.json').write_text('{"schemaVersion":999}')
        before = self.hashes()
        self.call('list', code=65)
        self.call('add', code=65)
        self.assertEqual(self.hashes(), before)
    def test_symlink_files_and_invalid_stdin_rejected(self):
        self.folder.mkdir()
        sentinel = Path(self.temp.name)/'sentinel'
        sentinel.write_text('[]')
        (self.folder/'notes.json').symlink_to(sentinel)
        self.call('add', code=65)
        self.assertEqual(sentinel.read_text(), '[]')
        self.call('add', '--stdin', stdin=b'\xff', code=64)
        self.call('add', '--stdin', stdin=b'x'*(8*1024*1024+1), code=64)
    def test_two_processes_serialize_or_report_busy(self):
        self.add()
        processes = [subprocess.Popen([str(CLI), '--data-dir', str(self.folder), 'add', '--text', str(i)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env) for i in range(12)]
        successes = 0
        for p in processes:
            out, err = p.communicate()
            self.assertIn(p.returncode, [0, 75])
            if p.returncode == 0:
                self.assertTrue(json.loads(out)['ok']); successes += 1
            else:
                self.assertEqual(json.loads(err)['error']['code'], 'locked')
        self.assertEqual(len(self.call('list')), 1 + successes)
    def test_app_store_honors_trash_and_preserves_sync_identity(self):
        first = self.add('one')
        second = self.add('two')
        self.call('delete', first, second)
        env = dict(self.env, STICKIES_DATA_DIR=str(self.folder))
        probe = Path('build/bin/cli-store-probe').resolve()
        result = subprocess.run([str(probe)], capture_output=True, env=env, check=True)
        state = json.loads(result.stdout)
        self.assertEqual((state['active'], state['trashed'], state['syncValues']), (0, 2, 2))
        subprocess.run([str(probe), 'remote-edit'], capture_output=True, env=env, check=True)
        self.call('restore', first, second)
        self.assertEqual(self.call('get', first)['text'], 'Remote update while locally trashed')
        result = subprocess.run([str(probe)], capture_output=True, env=env, check=True)
        self.assertEqual(json.loads(result.stdout)['active'], 2)
    def test_running_app_store_refuses_cli_without_data_loss(self):
        first = self.add('saved app content')
        before = self.hashes()
        env = dict(self.env, STICKIES_DATA_DIR=str(self.folder))
        probe = Path('build/bin/cli-store-probe').resolve()
        p = subprocess.Popen([str(probe), 'hold'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            self.assertEqual(p.stdout.readline(), b'ready\n')
            error = self.call('edit', first, '--text', 'must not overwrite', code=75)
            self.assertIn('Quit it normally', error['message'])
            self.call('delete', first, code=75)
            self.call('list', code=75)
            self.assertEqual(self.hashes(), before)
        finally:
            p.communicate(input=b'\n', timeout=10)
        self.assertEqual(p.returncode, 0)
        self.assertEqual(self.call('get', first)['text'], 'saved app content')
    def test_atomic_write_permission_failure_preserves_content(self):
        first = self.add()
        before = self.hashes()
        self.folder.chmod(0o500)
        try:
            self.call('edit', first, '--text', 'must not save', code=74)
            self.call('delete', first, code=74)
            self.assertEqual(self.hashes(), before)
        finally:
            self.folder.chmod(0o700)
    def test_slow_stdin_is_read_until_eof(self):
        p = subprocess.Popen([str(CLI), '--data-dir', str(self.folder), 'add', '--stdin'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=self.env)
        p.stdin.write(b'first\n'); p.stdin.flush(); time.sleep(.1)
        p.stdin.write('second 工作'.encode()); p.stdin.close(); p.stdin = None
        out, err = p.communicate()
        self.assertEqual(p.returncode, 0, err)
        self.assertEqual(json.loads(out)['data']['text'], 'first\nsecond 工作')

if __name__ == '__main__':
    unittest.main()
