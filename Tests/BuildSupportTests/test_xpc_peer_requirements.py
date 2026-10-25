"""Exercise owned XPC peer identity without an engine or protected app process."""
import hashlib
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


@unittest.skipUnless(sys.platform == 'darwin', 'macOS Security/XPC boundary')
class XPCPeerRequirementTests(unittest.TestCase):
    def test_matching_peer_echoes_and_mismatched_peer_rejects(self):
        key = hashlib.sha256(str(ROOT).encode()).hexdigest()[:12]
        shared = Path(os.environ.get(
            'DUST3D_BUILD_ROOT', str(Path(tempfile.gettempdir()) / ('dust3d-native-' + key))))
        shared.mkdir(parents=True, exist_ok=True)
        cache = shared / 'clang'
        cache.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='xpc-peer-', dir=shared) as directory:
            binary = Path(directory) / 'peer-acceptance'
            sources = [ROOT / 'Sources' / 'Dust3DKit' / name for name in [
                'HelperSignaturePolicy.swift', 'HelperCodeSignatureVerifier.swift', 'HelperXPCPeerFactory.swift']]
            sources.append(ROOT / 'Tests' / 'IntegrationSupport' / 'HelperXPCPeerAcceptance.swift')
            compile_result = subprocess.run([
                'xcrun', 'swiftc', '-swift-version', '6', '-strict-concurrency=complete', '-warnings-as-errors',
                '-module-cache-path', str(cache), '-parse-as-library',
                *map(str, sources), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)
            # Establish the same owned-fixture precondition regardless of linker signing defaults.
            signing = subprocess.run(
                ['/usr/bin/codesign', '--force', '--sign', '-', str(binary)], capture_output=True, text=True)
            self.assertEqual(signing.returncode, 0, signing.stdout + signing.stderr)
            signature = subprocess.run(
                ['/usr/bin/codesign', '-d', '--verbose=4', str(binary)], capture_output=True, text=True)
            self.assertEqual(signature.returncode, 0, signature.stdout + signature.stderr)
            digest = re.search(r'^CDHash=([0-9a-f]{40})$', signature.stderr, re.MULTILINE)
            self.assertIsNotNone(digest, signature.stderr)
            result = subprocess.run([str(binary), digest.group(1)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Matching XPC peer echoed exact bytes', result.stdout)
            self.assertIn('mismatched peer rejected', result.stdout)
