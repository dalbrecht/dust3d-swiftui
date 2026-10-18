"""Keep executable provenance aligned with dependencies resolved by the current build."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class SwiftIdentityOrderingTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        temporary = Path(self.directory.name)
        self.root = temporary / 'source'
        (self.root / 'script').mkdir(parents=True)
        for name in ['swift.sh', 'build_paths.sh', 'build_identity.py']:
            shutil.copyfile(ROOT / 'script' / name, self.root / 'script' / name)
        self.state = temporary / 'state.json'
        self.build_root = temporary / 'cache'
        self.fake_tools = temporary / 'tools'
        self.fake_tools.mkdir()
        fake = self.fake_tools / 'xcrun'
        fake.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
state = pathlib.Path(os.environ['IDENTITY_TEST_STATE'])
arguments = sys.argv[1:]
if arguments[:2] == ['swift', 'package'] and arguments[-1] == 'resolve':
    if os.environ.get('IDENTITY_TEST_RESOLVE_FAILURE') == '1':
        print('Resolver fixture failure', file=sys.stderr)
        sys.exit(19)
    pathlib.Path('Package.resolved').write_text(json.dumps({'pins': [
        {'identity': 'dust3d-core', 'state': {'revision': 'd' * 40}}
    ]}))
    state.write_text(json.dumps({'resolved': True}))
elif arguments[:2] == ['swift', 'build']:
    previous = json.loads(state.read_text()) if state.exists() else {'resolved': False}
    previous['embedded'] = json.loads(pathlib.Path(arguments[-1]).read_text())
    state.write_text(json.dumps(previous))
else:
    print('Unexpected fake xcrun arguments: ' + repr(arguments), file=sys.stderr)
    sys.exit(21)
''')
        fake.chmod(0o755)
        (self.root / 'Package.swift').write_text('// intended dust3d-core revision: ' + 'd' * 40)
        (self.root / 'Package.resolved').write_text(json.dumps({
            'pins': [{'identity': 'dust3d-core', 'state': {'revision': 'b' * 40}}]
        }))
        for arguments in [
            ['init', '--quiet'], ['config', 'user.name', 'Build Identity Test'],
            ['config', 'user.email', 'build-identity@example.invalid'], ['add', '.'],
            ['commit', '--quiet', '-m', 'Initial fixture'],
        ]:
            subprocess.run(['git', '-C', str(self.root), *arguments], check=True, capture_output=True)
        self.environment = dict(os.environ, PATH=str(self.fake_tools) + os.pathsep + os.environ['PATH'],
                                DUST3D_BUILD_ROOT=str(self.build_root), IDENTITY_TEST_STATE=str(self.state))

    def run_wrapper(self):
        return subprocess.run(['bash', str(self.root / 'script/swift.sh'), 'build'], cwd=self.root,
                              env=self.environment, capture_output=True, text=True, timeout=30)

    def test_should_resolve_updated_manifest_before_embedding_core_identity(self):
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        state = json.loads(self.state.read_text())
        self.assertTrue(state['resolved'])
        self.assertEqual(state['embedded']['coreRevision'], 'd' * 40)
        self.assertTrue(state['embedded']['isDirty'])

    def test_should_stop_before_identity_capture_or_linking_when_resolution_fails(self):
        self.environment['IDENTITY_TEST_RESOLVE_FAILURE'] = '1'
        result = self.run_wrapper()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Resolver fixture failure', result.stderr)
        self.assertFalse(self.state.exists())
        self.assertFalse((self.build_root / 'identities').exists())
