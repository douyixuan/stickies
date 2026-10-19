"""Exercise the installer hash gate with a simulated checker, never user data."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

class PreflightTests(unittest.TestCase):
    def test_optimized_gate_rejects_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            codesign = root / "codesign"
            codesign.write_text("#!/bin/sh\nexit 0\n")
            codesign.chmod(0o700)
            candidate = root / "payload"
            checker = candidate / "Contents/MacOS/NoteDataCheck"
            checker.parent.mkdir(parents=True)
            checker.write_text('#!/bin/sh\nprintf changed > "$1"\n')
            checker.chmod(0o700)
            notes = root / "notes.json"
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
            script = Path(__file__).resolve().parents[1] / "scripts/preflight-install.py"
            for flags in [[], ["-O"]]:
                notes.write_text("original fixture")
                result = subprocess.run([sys.executable, *flags, str(script), str(candidate), str(notes)], env=env, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Data changed during preflight", result.stderr)
                self.assertNotIn("PASS:", result.stdout)

if __name__ == "__main__":
    unittest.main()
