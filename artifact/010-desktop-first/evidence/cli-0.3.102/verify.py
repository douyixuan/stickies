import platform
import fcntl, hashlib, importlib.util, json, os, pathlib, plistlib, subprocess, tempfile, unittest, uuid, zipfile, datetime
ROOT=pathlib.Path(__file__).resolve().parent
SOURCE=ROOT.parent/'cli-main-deb042e'
SHA='deb042eeb464f289af1275e415b5d6a9244070f2'
archive=next((SOURCE/'build/releases').glob('*deb042eeb464-universal2.zip'))
payload=ROOT/'payload'
with zipfile.ZipFile(archive) as z:
 prefix=next(n[:-len('Contents/Info.plist')] for n in z.namelist() if n.endswith('Contents/Info.plist'))
 for e in z.infolist():
  if not e.filename.startswith(prefix) or e.is_dir():continue
  rel=pathlib.Path(e.filename[len(prefix):]);assert not rel.is_absolute() and '..' not in rel.parts
  dst=payload/rel;dst.parent.mkdir(parents=True,exist_ok=True);dst.write_bytes(z.read(e));dst.chmod((e.external_attr>>16)&0o777)
cli=payload/'Contents/MacOS/istk'
info=plistlib.loads((payload/'Contents/Info.plist').read_bytes());assert info['StickiesGitCommit']==SHA
subprocess.run(['codesign','--verify','--deep','--strict',str(payload)],check=True)
arches=subprocess.check_output(['lipo','-archs',str(cli)],text=True).split();assert set(arches)=={'arm64','x86_64'}
env=dict(os.environ);env.pop('STICKIES_DATA_DIR',None);env['ISTK_TEST_BINARY']=str(cli);env['PYTHONDONTWRITEBYTECODE']='1'
steps=[]
def invoke(folder,*args,code=0,stdin=None):
 result=subprocess.run([str(cli),'--data-dir',str(folder),*args],input=stdin,text=True,capture_output=True,env=env)
 assert result.returncode==code,(args,result.returncode,result.stderr)
 value=json.loads(result.stdout if code==0 else result.stderr)
 assert value['ok']==(code==0)
 steps.append({'command':args[0],'expectedExit':code,'actualExit':result.returncode,'newProcess':True})
 return value.get('data') if code==0 else value['error']
def hashes(folder):
 return {p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in folder.iterdir() if p.is_file() and p.name!='notes.lock'}
with tempfile.TemporaryDirectory(prefix='istk-package-',dir='/tmp') as tmp:
 folder=pathlib.Path(tmp)/'profile'
 assert 'restore' in invoke(folder,'help')['commands']
 version=invoke(folder,'version');assert version['commit']==SHA and not folder.exists()
 note=invoke(folder,'add','--text','包内验收 Café 工作','--color','2');identity=note['id']
 assert invoke(folder,'get',identity)['text']==note['text']
 assert [x['id'] for x in invoke(folder,'list')]==[identity]
 updated='中文编辑\nCafé 保存重启\n'
 invoke(folder,'edit',identity,'--stdin',stdin=updated)
 assert invoke(folder,'get',identity)['text']==updated
 assert [x['id'] for x in invoke(folder,'search','cafe 保存')]==[identity]
 assert invoke(folder,'search','不存在')==[]
 beforeNotes=(folder/'notes.json').read_bytes()
 invoke(folder,'delete',identity)
 assert invoke(folder,'list')==[]
 assert invoke(folder,'get',identity,'--trash')['text']==updated
 assert [x['id'] for x in invoke(folder,'list','--trash')]==[identity]
 invoke(folder,'restore',identity)
 assert invoke(folder,'get',identity)['text']==updated
 assert invoke(folder,'list','--trash')==[]
 assert (folder/'notes.json').read_bytes()==beforeNotes
 before=hashes(folder)
 for args in [('edit','not-a-uuid','--text','bad'),('add','--color','9'),('unknown-command',)]:invoke(folder,*args,code=64)
 assert hashes(folder)==before
 with (folder/'notes.lock').open('rb') as lock:
  fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
  for args in [('list',),('edit',identity,'--text','locked')]:invoke(folder,*args,code=75)
  assert hashes(folder)==before
 assert invoke(folder,'get',identity)['text']==updated
 folder.chmod(0o500)
 try:
  invoke(folder,'edit',identity,'--text','denied',code=74)
  assert hashes(folder)==before
 finally:folder.chmod(0o700)
 assert invoke(folder,'get',identity)['text']==updated
 invoke(folder,'edit',identity,'--text','恢复写入成功')
 assert invoke(folder,'get',identity)['text']=='恢复写入成功'
 finalHashes=hashes(folder)
# Reuse existing packaged-CLI integration assertions, excluding the two headless Store probes.
os.environ.update(env)
spec=importlib.util.spec_from_file_location('packaged_cli_tests',SOURCE/'Tests/CLITests.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
names=[name for name in unittest.defaultTestLoader.getTestCaseNames(module.CLIIntegration) if name not in ['test_app_store_honors_trash_and_preserves_sync_identity','test_running_app_store_refuses_cli_without_data_loss']]
with (ROOT/'integration-tests.log').open('w') as log:
 result=unittest.TextTestRunner(stream=log,verbosity=2).run(unittest.TestSuite(module.CLIIntegration(name) for name in names))
assert result.wasSuccessful(), 'see integration-tests.log'
report={'source':SHA,'build':info['CFBundleVersion'],'version':version,'archive':str(archive),'archiveSHA256':hashlib.sha256(archive.read_bytes()).hexdigest(),'binary':str(cli),'binarySHA256':hashlib.sha256(cli.read_bytes()).hexdigest(),'architectures':arches,'timeUTC':datetime.datetime.now(datetime.timezone.utc).isoformat(),'steps':steps,'reusedTests':names,'reusedTestCount':result.testsRun,'allPassed':True,'finalSyntheticFileHashes':finalHashes,'data':'temporary synthetic profile; removed after run','GUIStarted':False,'realDataAccessed':False,'PATHChanged':False,'installed':False,'limits':[f'native {platform.machine()} execution only; other architecture presence checked','running GUI transport and GUI clicks not exercised','no schema migration, cloud transport or power-loss validation']}
(ROOT/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'build':report['build'],'source':SHA,'processInvocations':len(steps),'reusedTests':result.testsRun,'allPassed':True,'evidence':str(ROOT/'verification.json')},ensure_ascii=False))
