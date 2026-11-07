#!/usr/bin/env python3
"""Complete-profile backup/restore and failure tests using only synthetic data."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

spec = importlib.util.spec_from_file_location('backup', Path(__file__).resolve().parents[1] / 'scripts/profile-backup.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class BackupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='istk backup test ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.profile = self.root / 'synthetic'
        self.profile.mkdir()
        (self.profile / 'notes.lock').touch()
        for name in ('notes.json', 'layout.json', 'trash.json', 'preferences.json', 'command-journal.json'):
            (self.profile / name).write_text(json.dumps({'synthetic': name}))
        (self.profile / 'segments').mkdir()
        (self.profile / 'segments' / 'one.json').write_text('合成文本\nsecond line')
        (self.profile / 'empty').mkdir()
        self.archive = self.root / 'backup.zip'

    def test_full_profile_round_trip(self):
        before = module.inventory(self.profile)
        for args in [('backup', self.profile, self.archive), ('verify', self.archive),
                     ('restore', self.archive, self.root / 'restored')]:
            result = subprocess.check_output([sys.executable, str(Path(module.__file__)), *map(str, args)])
            self.assertEqual(json.loads(result)['status'], 'verified')
        self.assertEqual(module.inventory(self.root / 'restored'), before)
        self.assertEqual(module.inventory(self.profile), before)
        self.assertTrue((self.root / 'restored' / 'notes.lock').is_file())

    def test_backup_failure_never_publishes(self):
        before = module.inventory(self.profile)
        with patch.object(zipfile.ZipFile, 'writestr', side_effect=OSError('simulated full disk')):
            with self.assertRaises(OSError):
                module.backup(self.profile, self.archive)
        self.assertFalse(self.archive.exists())
        self.assertFalse(list(self.root.glob('*.partial')))
        self.assertEqual(module.inventory(self.profile), before)

    def test_restore_failure_never_publishes(self):
        module.backup(self.profile, self.archive)
        with patch.object(module.os, 'fsync', side_effect=OSError('simulated full disk')):
            with self.assertRaises(OSError):
                module.restore(self.archive, self.root / 'restored')
        self.assertFalse((self.root / 'restored').exists())
        self.assertFalse(list(self.root.glob('*.partial')))

    def test_lock_conflict_leaves_no_archive(self):
        with module.locked(self.profile):
            result = subprocess.run([sys.executable, str(Path(module.__file__)), 'backup',
                                     str(self.profile), str(self.archive)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.archive.exists())

    def test_corruption_leaves_no_restore(self):
        module.backup(self.profile, self.archive)
        with zipfile.ZipFile(self.archive) as z:
            entries = [(i, z.read(i)) for i in z.infolist()]
        with zipfile.ZipFile(self.archive, 'w') as z:
            for info, data in entries:
                z.writestr(info, b'changed' if info.filename == 'profile/notes.json' else data)
        with self.assertRaises(ValueError):
            module.restore(self.archive, self.root / 'restored')
        self.assertFalse((self.root / 'restored').exists())

    def test_no_overwrite_or_in_profile_backup(self):
        module.backup(self.profile, self.archive)
        old = self.archive.read_bytes()
        with self.assertRaises(ValueError):
            module.backup(self.profile, self.archive)
        with self.assertRaises(ValueError):
            module.backup(self.profile, self.profile / 'nested.zip')
        with self.assertRaises(ValueError):
            module.restore(self.archive, self.profile)
        self.assertEqual(self.archive.read_bytes(), old)

    def test_publish_race_does_not_replace_existing_backup(self):
        original_link = module.os.link
        def race(source, destination):
            Path(destination).write_bytes(b'other writer')
            return original_link(source, destination)
        with patch.object(module.os, 'link', side_effect=race):
            with self.assertRaises(FileExistsError):
                module.backup(self.profile, self.archive)
        self.assertEqual(self.archive.read_bytes(), b'other writer')

    def test_symlink_and_missing_lock_refused(self):
        (self.profile / 'link').symlink_to(self.profile / 'notes.json')
        with self.assertRaises(ValueError):
            module.backup(self.profile, self.archive)
        (self.profile / 'link').unlink()
        (self.profile / 'notes.lock').unlink()
        with self.assertRaises(OSError):
            module.backup(self.profile, self.archive)
        self.assertFalse(self.archive.exists())


if __name__ == '__main__':
    unittest.main()
