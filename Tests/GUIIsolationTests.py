"""Test the GUI harness storage guard without starting AppKit."""
import os
import pathlib
import subprocess
import tempfile
import uuid

exe = str(pathlib.Path('build/store-smoke').resolve())
env = dict(os.environ)
env.pop('STICKIES_DATA_DIR', None)
env.pop('STICKIES_GUI_SMOKE_TOKEN', None)


def run(environment, expected):
    result = subprocess.run(
        [exe, '--check-isolation'], env=environment,
        capture_output=True, text=True, timeout=10,
    )
    assert result.returncode == expected, (result.returncode, result.stdout, result.stderr)


run(env, 64)
with tempfile.TemporaryDirectory(prefix='stickies-test.') as directory:
    token = str(uuid.uuid4())
    fixture_env = dict(env, STICKIES_DATA_DIR=directory, STICKIES_GUI_SMOKE_TOKEN=token)
    run(fixture_env, 64)
    marker = pathlib.Path(directory) / '.gui-smoke-token'
    marker.write_text(str(uuid.uuid4()))
    run(fixture_env, 64)
    marker.write_text(token)
    run(fixture_env, 0)
    assert list(pathlib.Path(directory).iterdir()) == [marker]
with tempfile.TemporaryDirectory(prefix='wrong-prefix.') as directory:
    token = str(uuid.uuid4())
    (pathlib.Path(directory) / '.gui-smoke-token').write_text(token)
    run(dict(env, STICKIES_DATA_DIR=directory, STICKIES_GUI_SMOKE_TOKEN=token), 64)
print('PASS: 5 isolation cases; no GUI or note files created')
