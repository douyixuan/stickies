import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('snapshot', Path(__file__).resolve().parents[1] / 'scripts/build_snapshot.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class SnapshotTests(unittest.TestCase):
    def test_isolated_clean_and_dirty_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / 'repo'; root.mkdir()
            def git(*args):
                return subprocess.check_output(['git', *args], cwd=root)
            git('init', '-q'); git('config', 'user.name', 'Fixture'); git('config', 'user.email', 'fixture@example.invalid')
            for name in ('Stickies/note.swift', 'Tools/istk.swift', 'project.yml'):
                p = root / name; p.parent.mkdir(exist_ok=True); p.write_text('original')
            git('add', '.'); git('commit', '-qm', 'fixture')
            clean = Path(temp) / 'clean'; clean.mkdir()
            self.assertTrue(m.capture(root, clean)['clean'])
            p = root / 'Stickies/note.swift'; p.write_text('transient edit')
            self.assertEqual((clean / 'Stickies/note.swift').read_text(), 'original')
            dirty = Path(temp) / 'dirty'; dirty.mkdir()
            (root / 'Tools/new.swift').write_text('untracked')
            meta = m.capture(root, dirty)
            self.assertFalse(meta['clean'])
            p.write_text('original'); (root / 'Tools/new.swift').unlink()
            self.assertEqual((dirty / 'Stickies/note.swift').read_text(), 'transient edit')
            self.assertEqual((dirty / 'Tools/new.swift').read_text(), 'untracked')
            self.assertEqual((clean / 'Tools/istk.swift').read_text(), 'original')
            linked = root / 'Tools/link.swift'; linked.symlink_to(p)
            bad = Path(temp) / 'bad'; bad.mkdir()
            with self.assertRaises(ValueError):
                m.capture(root, bad)
            linked.unlink()
            (root / 'Tools').rename(root / 'external-tools')
            (root / 'Tools').symlink_to(root / 'external-tools', target_is_directory=True)
            bad_top = Path(temp) / 'bad-top'
            bad_top.mkdir()
            with self.assertRaises(ValueError):
                m.capture(root, bad_top)

if __name__ == '__main__': unittest.main()
