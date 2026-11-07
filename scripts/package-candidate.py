#!/usr/bin/env python3
"""Package a verified development candidate; never install, launch GUI, or release."""
import hashlib
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
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
cli_archive = output / f'istk-candidate-{source}.zip'
assert not archive.exists() and not cli_archive.exists(), 'Use a fresh build output; never replace a verified archive'
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
    # A relocatable CLI-only candidate; exactly the verified App's executable.
    cli_stage = temp / 'CLI distribution'
    cli_stage.mkdir()
    shutil.copy2(cli, cli_stage / 'istk')
    cli_manifest = dict(sourceSHA=source, cliVersion=version['version'],
                        schemaVersion=version['schemaVersion'], minimumMacOS='14.0',
                        architectures=cli_archs, binarySHA256=sha(cli),
                        candidateOnly=True, notarized=False)
    (cli_stage / 'manifest.json').write_text(json.dumps(cli_manifest, indent=2) + '\n')
    (cli_stage / 'USAGE.txt').write_text("""iStickies2 istk CLI candidate (not Apple Stickies / stk).
No app launch, PATH modification or installation is required.
From this extracted directory, run:
  ./istk help
  ./istk version
  profile="$(mktemp -d -t istk-cli-demo)"
  ./istk --dir "$profile" add 'Synthetic example'
  ./istk --dir "$profile" list
  ./istk --dir "$profile" search 'Synthetic'
  ./istk --dir "$profile" get '<id returned by add>'
Each invocation opens a fresh process and reads persisted data.
Every data command requires --dir; there is no implicit daily profile.
Use quoted absolute executable paths when invoking from another directory.
While an App owns the same profile lock, reads work but writes are refused.
Unreadable profiles and pending old command journals fail without bypassing locks.
First writes upgrade old notes to schema 10: old 0.3 clients cannot read it.
Do not point this trial at daily data. Real upgrades require a complete verified
quiescent profile backup; rollback restores the whole profile, not just the app.
manifest.json identifies the source, architecture and binary hash. This is an
ad-hoc signed CI candidate, not a stable Homebrew release or notarized product.
""")
    subprocess.run(['ditto', '-c', '-k', str(cli_stage), str(cli_archive)], check=True)
    cli_extract = temp / 'standalone extracted CLI'
    subprocess.run(['ditto', '-x', '-k', str(cli_archive), str(cli_extract)], check=True)
    delivered = cli_extract / 'istk'
    assert os.access(delivered, os.X_OK) and sha(delivered) == sha(cli)
    assert arches(delivered) == cli_archs
    assert json.loads((cli_extract / 'manifest.json').read_text()) == cli_manifest
    subprocess.run(['codesign', '--verify', '--strict', str(delivered)], check=True)
    assert json.loads(run(str(delivered), 'version')) == version
    assert subprocess.run([str(delivered), 'list'], stdout=subprocess.PIPE,
                          stderr=subprocess.PIPE).returncode == 64
    report['standaloneCLI'] = dict(archive=cli_archive.name, sha256=sha(cli_archive),
                                   binarySHA256=sha(delivered), verification='passed')
    (output / (cli_archive.name + '.sha256')).write_text(sha(cli_archive) + '  ' + cli_archive.name + '\n')
    (output / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
    (output / (archive.name + '.sha256')).write_text(archive_hash + '  ' + archive.name + '\n')
    print(json.dumps(report, indent=2))
