"""Local AF_UNIX tests with temporary profiles and a host that never creates NSApplication."""
import json
import os
from pathlib import Path
import socket
import struct
import subprocess
import tempfile
import time
import unittest
import uuid

CLI = str(Path('build/bin/istk').resolve())
HOST = str(Path('build/bin/command-channel-host').resolve())

class CommandChannelTests(unittest.TestCase):
    def setUp(self):
        # /tmp keeps AF_UNIX paths within the macOS 104-byte limit.
        self.temp = tempfile.TemporaryDirectory(prefix='istk-channel-',dir='/tmp')
        self.folder = Path(self.temp.name)
        self.env = dict(os.environ,STICKIES_DATA_DIR=str(self.folder))
        self.host = None
    def tearDown(self):
        if self.host:
            self.host.communicate(input=b'\n' if self.host.poll() is None else None,timeout=20)
        self.temp.cleanup()
    def start(self,mode='normal'):
        self.host = subprocess.Popen([HOST,mode],env=self.env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        line = self.host.stdout.readline()
        if line != b'ready\n':
            _, err = self.host.communicate(timeout=20)
            self.fail((line, err))
    def stop(self):
        out,err=self.host.communicate(input=b'\n',timeout=15)
        self.assertEqual(self.host.returncode,0,err)
        self.assertIn(b'stopped',out)
        self.host=None
    def cli(self,*args,code=0,stdin=None):
        p=subprocess.run([CLI,*args],env=self.env,input=stdin,capture_output=True,timeout=20)
        self.assertEqual(p.returncode,code,(p.stdout,p.stderr))
        return json.loads(p.stdout if code==0 else p.stderr)
    def raw(self,payload):
        peer=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        peer.settimeout(10)
        peer.connect(str(self.folder/'istk.sock'))
        data=json.dumps(payload).encode() if not isinstance(payload,bytes) else payload
        peer.sendall(struct.pack('!I',len(data))+data)
        return peer
    def reply(self,peer):
        def exact(n):
            value=b''
            while len(value)<n:
                part=peer.recv(n-len(value))
                self.assertTrue(part)
                value+=part
            return value
        size=struct.unpack('!I',exact(4))[0]
        result=json.loads(exact(size));peer.close();return result
    def request(self,identity=None,text='raw'):
        return {'version':1,'request':{'id':identity or str(uuid.uuid4()),'command':'add','ids':[],'text':text}}
    def test_store_lifecycle_and_visible_failure_state(self):
        self.start('lifecycle')
        self.assertEqual(self.cli('add','--text','after restart')['data']['text'],'after restart')
        self.stop()
        self.assertFalse((self.folder/'istk.sock').exists())
    def test_live_crud_search_and_restart(self):
        self.start()
        first=self.cli('add','--stdin',stdin='工作 café\nline'.encode())['data']['id']
        self.assertEqual(len(self.cli('search','cafe 工作')['data']),1)
        self.cli('edit',first,'--text','new')
        self.assertEqual(self.cli('get',first)['data']['text'],'new')
        self.cli('delete',first)
        self.assertEqual(self.cli('list')['data'],[])
        self.assertEqual(len(self.cli('list','--trash')['data']),1)
        self.cli('restore',first)
        self.stop()
        self.assertEqual(self.cli('get',first)['data']['text'],'new')
        self.start()
        self.assertEqual(self.cli('get',first)['data']['text'],'new')
    def test_duplicate_id_and_result_query(self):
        self.start()
        identity=str(uuid.uuid4())
        one=self.cli('add','--text','once','--request-id',identity)
        two=self.cli('add','--text','once','--request-id',identity)
        self.assertEqual(one,two)
        self.cli('add','--text','changed','--request-id',identity,code=64)
        self.assertEqual(self.cli('result',identity)['data']['notes'][0]['id'],one['data']['id'])
        self.stop()
        self.assertEqual(self.cli('add','--text','once','--request-id',identity)['data'],one['data'])
    def test_invalid_requests_do_not_mutate(self):
        self.start()
        for payload in [b'invalid JSON',{'version':99,'request':self.request()['request']},self.request(text='valid')|{'version':3}]:
            self.assertEqual(self.reply(self.raw(payload))['status'],64)
        bad=self.request();bad['request']['command']='erase-everything'
        self.assertEqual(self.reply(self.raw(bad))['status'],64)
        self.assertEqual(self.cli('list')['data'],[])
    def test_client_disconnect_keeps_one_durable_result(self):
        self.start()
        identity=str(uuid.uuid4())
        peer=self.raw(self.request(identity=identity));peer.close()
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            result=subprocess.run([CLI,'result',identity],env=self.env,capture_output=True)
            if result.returncode==0: break
            time.sleep(.05)
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(self.cli('list')['data']),1)
    def test_timeout_reports_unknown_and_same_id_is_safe(self):
        self.start('delay')
        identity=str(uuid.uuid4())
        result=self.cli('add','--text','late','--request-id',identity,code=74)
        self.assertEqual(result['error']['code'],'outcome_unknown')
        self.assertEqual(result['requestID'].lower(),identity)
        time.sleep(1.2)
        self.stop()
        self.assertEqual(len(self.cli('list')['data']),1)
        self.assertEqual(self.cli('add','--text','late','--request-id',identity)['data']['text'],'late')
        self.assertEqual(len(self.cli('list')['data']),1)
    def test_host_crash_restart_replays_same_request(self):
        for stage in ['prepared','notesWritten','ledgerWritten']:
            with self.subTest(stage=stage):
                self.start('crash-'+stage)
                identity=str(uuid.uuid4())
                result=self.cli('add','--text',stage,'--request-id',identity,code=74)
                self.assertEqual(result['error']['code'],'outcome_unknown')
                self.host.communicate(timeout=10)
                self.assertEqual(self.host.returncode,91)
                self.host=None
                self.start()
                self.assertEqual(self.cli('add','--text',stage,'--request-id',identity)['data']['text'],stage)
                self.assertEqual(self.cli('result',identity)['data']['notes'][0]['text'],stage)
                self.stop()
        self.assertEqual(len(self.cli('list')['data']),3)
    def test_slow_drip_slots_expire_and_idle_listener_survives(self):
        self.start()
        peers=[]
        try:
            for _ in range(8):
                peer=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
                peer.settimeout(2)
                peer.connect(str(self.folder/'istk.sock'))
                peer.sendall(struct.pack('!I',100)+b'{')
                peers.append(peer)
            started=time.monotonic()
            while time.monotonic()-started < 6:
                time.sleep(.5)
                for peer in peers:
                    try: peer.sendall(b' ')
                    except OSError: pass
            self.assertEqual(self.cli('list')['data'],[])
            for peer in peers:
                # A timeout reply or EOF proves that the partial request expired.
                self.assertNotEqual(peer.recv(1),None)
            time.sleep(5.2)
            self.assertEqual(self.cli('list')['data'],[])
        finally:
            for peer in peers: peer.close()
    def test_concurrent_duplicate_requests_commit_once(self):
        self.start()
        identity=str(uuid.uuid4())
        peers=[self.raw(self.request(identity)) for _ in range(8)]
        replies=[self.reply(peer) for peer in peers]
        self.assertTrue(all(reply==replies[0] for reply in replies))
        self.assertEqual(len(self.cli('list')['data']),1)
    def test_endpoint_permissions_and_oversized_frame(self):
        self.start()
        endpoint=self.folder/'istk.sock'
        self.assertEqual(endpoint.stat().st_mode & 0o777,0o600)
        peer=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        peer.connect(str(endpoint));peer.sendall(struct.pack('!I',16*1024*1024+1))
        self.assertEqual(self.reply(peer)['status'],64)
        endpoint.chmod(0o666)
        self.cli('list',code=65)
        endpoint.chmod(0o600)
        endpoint.unlink();endpoint.symlink_to(self.folder/'absent')
        self.cli('list',code=65)
        endpoint.unlink()

    def test_shutdown_incomplete_request_never_executes(self):
        self.start()
        peer=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        peer.connect(str(self.folder/'istk.sock'))
        peer.sendall(struct.pack('!I',100)+b'{')
        self.stop();peer.close()
        self.assertEqual(self.cli('list')['data'],[])
        self.assertFalse((self.folder/'istk.sock').exists())

if __name__=='__main__': unittest.main()
