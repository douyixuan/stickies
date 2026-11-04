#!/usr/bin/env python3
"""Package a verified development candidate; never install, launch GUI, or release."""
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import subprocess
import tempfile

if not __debug__:
    raise SystemExit("Candidate verification requires Python assertions; disable optimization")

ROOT = Path(__file__).resolve().parent.parent
os.chdir(ROOT)

def run(*args, **kwargs):
    return subprocess.check_output(args, **kwargs)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def arches(path):
    return sorted(run('xcrun', 'lipo', '-archs', str(path), text=True).split())

source = run('git', 'rev-parse', 'HEAD', text=True).strip()
subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--'], check=True)
app = ROOT / 'build/iStickies2.app'
assert app.is_dir(), 'Build the app first'
output = ROOT / 'build/candidate'
output.mkdir(parents=True, exist_ok=True)
archive = output / f'iStickies2-candidate-{source}.zip'
assert not archive.exists(), 'Use a fresh build output; never replace a verified archive'
with tempfile.TemporaryDirectory(prefix='istk candidate ') as temp:
    temp = Path(temp)
    staged = temp / 'stage/iStickies2.app'
    subprocess.run(['ditto', str(app), str(staged)], check=True)
    info_path = staged / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if info.get('StickiesBuildSourceSHA') != source or info.get('StickiesBuildSourceClean') is not True:
        raise SystemExit('Rebuild the app from this clean source HEAD before packaging')
    info.update(CFBundleShortVersionString='0.0.0', CFBundleVersion='0',
                StickiesCandidate=True, StickiesGitCommit=source)
    info_path.write_bytes(plistlib.dumps(info))
    subprocess.run(['codesign', '--force', '--deep', '--sign', '-', str(staged)], check=True)
    subprocess.run(['ditto', '-c', '-k', '--keepParent', str(staged), str(archive)], check=True)
    archive_hash = sha(archive)
    extracted = temp / 'extracted app'
    subprocess.run(['ditto', '-x', '-k', str(archive), str(extracted)], check=True)
    restored = extracted / 'iStickies2.app'
    actual = plistlib.loads((restored / 'Contents/Info.plist').read_bytes())
    assert actual == info and actual['StickiesGitCommit'] == source
    assert actual['CFBundleIdentifier'] == 'dev.douyixuan.stickies'
    assert actual['LSMinimumSystemVersion'] == '14.0'
    executable = actual['CFBundleExecutable']
    assert Path(executable).name == executable and executable
    app_bin = restored / 'Contents/MacOS' / executable
    cli = restored / 'Contents/MacOS/istk'
    assert os.access(app_bin, os.X_OK) and os.access(cli, os.X_OK)
    app_archs, cli_archs = arches(app_bin), arches(cli)
    assert app_archs and app_archs == cli_archs
    assert set(app_archs) <= {'arm64', 'x86_64'}
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(restored)], check=True)
    subprocess.run(['codesign', '--verify', '--strict', str(cli)], check=True)
    version = json.loads(run(str(cli), 'version'))
    assert version == {'version': '1.0', 'schemaVersion': 10}
    env = dict(os.environ, ISTK_TEST_BINARY=str(cli))
    env.pop('STICKIES_DATA_DIR', None)
    with (output / 'cli-check.log').open('wb') as log:
        subprocess.run(['bash', 'scripts/test-cli.sh'], env=env, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    assert sha(archive) == archive_hash
    report = dict(sourceSHA=source, archive=archive.name, sha256=archive_hash,
                  inputSHA256=actual.get('StickiesBuildInputSHA256'),
                  candidateOnly=True, version=actual['CFBundleShortVersionString'],
                  build=actual['CFBundleVersion'], bundleID=actual['CFBundleIdentifier'],
                  appArchitectures=app_archs, cliArchitectures=cli_archs,
                  executedHostArchitecture=platform.machine(),
                  appSHA256=sha(app_bin), cliSHA256=sha(cli),
                  signature='ad-hoc verified after archive extraction', notarized=False,
                  isolatedCLIRegression='passed', GUIAccepted=False, installed=False)
    (output / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / (archive.name + '.sha256')).write_text(archive_hash + '  ' + archive.name + '\n')
    print(json.dumps(report, indent=2))
