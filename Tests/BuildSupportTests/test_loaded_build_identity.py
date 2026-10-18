"""Exercise the production loaded-image reader across replacement of its on-disk executable."""
import json
from pathlib import Path
import selectors
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'darwin', 'The loaded-image reader uses the macOS Mach-O loader')
class LoadedBuildIdentityTests(unittest.TestCase):
    def test_running_process_keeps_loaded_identity_and_restart_reads_replacement(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            main = root / 'main.swift'
            main.write_text('''import Foundation
let identity = RuntimeBuildIdentity.current
func report() throws {
    let revision = try identity.metadata.get().sourceRevision
    FileHandle.standardOutput.write(Data((revision + "\\n").utf8))
}
try report()
while readLine() != nil { try report() }
''')
            def compile_identity(revision, output):
                metadata = root / (revision[0] + '.json')
                metadata.write_text(json.dumps({
                    'schemaVersion': 1, 'sourceRevision': revision, 'coreRevision': 'b' * 40,
                    'sourceDigest': 'c' * 64, 'isDirty': False,
                }))
                subprocess.run([
                    'xcrun', 'swiftc', '-swift-version', '6', '-warnings-as-errors',
                    str(ROOT / 'Sources/Dust3DRendering/BuildIdentityMetadata.swift'),
                    str(ROOT / 'Sources/Dust3DRendering/RuntimeBuildIdentity.swift'), str(main),
                    '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__dust3d_build',
                    '-Xlinker', str(metadata), '-o', str(output),
                ], check=True, capture_output=True, timeout=90)

            executable = root / 'identity-probe'
            replacement = root / 'replacement-probe'
            compile_identity('a' * 40, executable)
            child = subprocess.Popen([str(executable)], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE)
            try:
                with selectors.DefaultSelector() as selector:
                    selector.register(child.stdout, selectors.EVENT_READ)
                    self.assertTrue(selector.select(timeout=20), 'Startup identity capture timed out')
                    self.assertEqual(child.stdout.readline().decode().strip(), 'a' * 40)
                compile_identity('d' * 40, replacement)
                replacement.replace(executable)
                output, error = child.communicate(input=b'\n', timeout=20)
                self.assertEqual(child.returncode, 0, error.decode())
                self.assertEqual(output.decode().strip(), 'a' * 40)
                restarted = subprocess.run([str(executable)], input=b'', capture_output=True, timeout=20, check=True)
                self.assertEqual(restarted.stdout.decode().strip(), 'd' * 40)
            finally:
                if child.poll() is None:
                    child.kill()
                    child.wait(timeout=10)
