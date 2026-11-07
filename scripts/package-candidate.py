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
from cli_release import archive_bytes

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
    assert version == {'version': '1.0.0', 'schemaVersion': 10}
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
    # Build separate versioned CLI release assets from the newly compiled,
    # verified source version. App/candidate manifests remain unchanged.
    assert cli_archs == ['arm64'], 'CLI 1.0.0 distribution supports ARM64 only'
    release_dir = ROOT / 'build/cli-release'
    release_dir.mkdir(parents=True, exist_ok=False)
    release_name = f"istk-{version['version']}-macos-arm64.zip"
    release_manifest = dict(sourceSHA=source, releaseVersion=version['version'],
                            cliVersion=version['version'], schemaVersion=10,
                            minimumMacOS='14.0', architectures=cli_archs,
                            binarySHA256=sha(cli), candidateOnly=False,
                            signature='ad-hoc', notarized=False)
    usage = (cli_stage / 'USAGE.txt').read_text().replace(
        'istk CLI candidate', 'istk CLI ' + version['version']).replace(
        'ad-hoc signed CI candidate, not a stable Homebrew release or notarized product.',
        'ad-hoc signed CLI build. It is not notarized and does not install or validate the GUI App.')
    files = {'istk': cli.read_bytes(),
             'manifest.json': (json.dumps(release_manifest, indent=2, sort_keys=True) + '\n').encode(),
             'USAGE.txt': usage.encode()}
    encoded = archive_bytes(files)
    assert encoded == archive_bytes(files), 'Archive encoding must be reproducible'
    release_archive = release_dir / release_name
    release_archive.write_bytes(encoded)
    release_extract = temp / 'versioned CLI release'
    subprocess.run(['ditto', '-x', '-k', str(release_archive), str(release_extract)], check=True)
    release_cli = release_extract / 'istk'
    assert sha(release_cli) == sha(cli) and os.access(release_cli, os.X_OK)
    assert arches(release_cli) == cli_archs
    subprocess.run(['codesign', '--verify', '--strict', str(release_cli)], check=True)
    assert json.loads(run(str(release_cli), 'version')) == version
    with (release_dir / 'cli-check.log').open('wb') as log:
        subprocess.run(['bash', 'scripts/test-cli.sh'],
                       env=dict(env, ISTK_TEST_BINARY=str(release_cli)),
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    release_report = dict(sourceSHA=source, ciRunID=int(os.environ.get('GITHUB_RUN_ID', '0')),
                          releaseVersion=version['version'], isolatedCLIRegression='passed',
                          signature='ad-hoc verified after extraction', notarized=False,
                          executedHostArchitecture=platform.machine(),
                          standaloneCLI=dict(archive=release_name, sha256=sha(release_archive),
                                             binarySHA256=sha(release_cli), verification='passed'))
    (release_dir / 'verification.json').write_text(json.dumps(release_report, indent=2) + '\n')
    (release_dir / (release_name + '.sha256')).write_text(sha(release_archive) + '  ' + release_name + '\n')
    print(json.dumps(report, indent=2))
