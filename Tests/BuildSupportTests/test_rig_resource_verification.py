"""Verify copied resources, including corruption and incomplete packaging failures."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RigResourceVerificationTests(unittest.TestCase):
    def test_accepts_exact_copy_and_rejects_changed_and_missing_template(self):
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / 'SDK.bundle'
            templates = bundle / 'RigTemplates'
            shutil.copytree(ROOT / 'Sources/Dust3DKit/RigTemplates', templates)
            def check():
                return subprocess.run([sys.executable, str(ROOT / 'script/check_rig_resources.py'), str(bundle)],
                                      capture_output=True, text=True, timeout=10)
            good = check()
            self.assertEqual(good.returncode, 0, good.stderr)
            target = templates / 'rig_fish.xml'
            original = target.read_bytes()
            changed = bytes([original[0] ^ 1]) + original[1:]
            self.assertEqual(len(changed), len(original))
            target.write_bytes(changed)
            damaged = check()
            self.assertNotEqual(damaged.returncode, 0)
            self.assertIn('rig_fish.xml', damaged.stderr)
            target.unlink()
            missing = check()
            self.assertNotEqual(missing.returncode, 0)
            self.assertIn('rig_fish.xml', missing.stderr)
