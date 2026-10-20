"""Keep SwiftPM from compiling the quarantined GLB material catalog API."""
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
_specification = importlib.util.spec_from_file_location(
    'glb_catalog_quarantine', ROOT / 'script/glb_catalog_quarantine.py')
_module = importlib.util.module_from_spec(_specification)
_specification.loader.exec_module(_module)
quarantine_violation = _module.quarantine_violation


class GlbCatalogQuarantineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.core = Path(self.directory.name) / 'core'
        self.header = self.core / 'native/Engine/include/Dust3DBridge.h'
        self.header.parent.mkdir(parents=True)
        self.header.write_text('/* Existing supported bridge. */\n')
        (self.core / 'Package.swift').write_text('sources: ["GlbReader.cc"],\n')
        (self.core / 'CMakeLists.txt').write_text('native/Engine/GlbReader.cc\n')

    def assert_rejected(self, diagnostic):
        violation = quarantine_violation(self.core)
        self.assertIsNotNone(violation)
        self.assertIn('GLB catalog quarantine', violation)
        self.assertIn(diagnostic, violation)

    def test_should_admit_supported_bridge_without_catalog_sources(self):
        self.assertIsNone(quarantine_violation(self.core))

    def test_should_reject_missing_bridge_and_restored_catalog_sources(self):
        self.header.unlink()
        self.assert_rejected('public bridge header is missing')
        self.header.write_text('void dust3d_glb_material_catalog_load(void);\n')
        self.assert_rejected('unfinished C API must remain unavailable')
        self.header.write_text('typedef struct Dust3DGlbMaterialCatalog Dust3DGlbMaterialCatalog;\n')
        self.assert_rejected('unfinished C API must remain unavailable')
        self.header.write_text('/* Existing supported bridge. */\n')
        (self.core / 'native/Engine/GlbMaterialCatalog.cc').write_text('/* quarantined */\n')
        self.assert_rejected('unfinished implementation was restored')
        (self.core / 'native/Engine/GlbMaterialCatalog.cc').unlink()
        (self.core / 'Package.swift').write_text('sources: ["GlbMaterialCatalog.cc"],\n')
        self.assert_rejected('unfinished implementation was restored')
        (self.core / 'Package.swift').write_text('sources: ["GlbReader.cc"],\n')
        (self.core / 'CMakeLists.txt').write_text('native/Engine/GlbMaterialCatalog.cc\n')
        self.assert_rejected('unfinished implementation was restored')
        (self.core / 'CMakeLists.txt').write_text('native/Engine/GlbReader.cc\n')
        self.assertIsNone(quarantine_violation(self.core))

    def test_script_should_reject_an_absent_checkout(self):
        result = subprocess.run(
            [sys.executable, str(ROOT / 'script/glb_catalog_quarantine.py'),
             '--core', str(self.core / 'missing')],
            capture_output=True, text=True, timeout=20)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('GLB catalog quarantine', result.stderr)


if __name__ == '__main__':
    unittest.main()
