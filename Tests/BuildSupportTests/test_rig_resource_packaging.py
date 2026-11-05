"""Exercise the real extension packager with inert binaries and system-tool stubs."""
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]


class RigResourcePackagingTests(unittest.TestCase):
    def test_both_extensions_receive_the_prebuilt_sdk_resource_bundle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            app = root / 'Editor.app'
            contents = app / 'Contents'
            contents.mkdir(parents=True)
            (contents / 'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'org.dust3d.editor'}))
            binaries = root / 'binaries'
            binaries.mkdir()
            names = ['Dust3DQuickLookExtension', 'Dust3DThumbnailExtension']
            for name in names:
                (binaries / name).write_bytes(b'inert fixture')
            for name in ['Dust3DNative_Dust3DRendering.bundle', 'Dust3DNative_Dust3DKit.bundle']:
                bundle = binaries / name
                bundle.mkdir()
                (bundle / 'fixture').write_bytes(b'resource identity')
            tools = root / 'tools'
            tools.mkdir()
            for name in ['codesign', 'xattr']:
                tool = tools / name
                tool.write_text('#!/bin/sh\nexit 0\n')
                tool.chmod(0o755)
            result = subprocess.run(
                ['bash', str(ROOT / 'script/package_file_preview_extensions.sh'), str(app), str(binaries)],
                env=dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH']),
                capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            for name in names:
                resource = contents / 'PlugIns' / (name + '.appex') / 'Contents/Resources/Dust3DNative_Dust3DKit.bundle/fixture'
                self.assertEqual(resource.read_bytes(), b'resource identity')
