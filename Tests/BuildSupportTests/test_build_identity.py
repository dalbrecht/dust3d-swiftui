"""Verify source identity generation with isolated, disposable Git repositories."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / 'script' / 'build_identity.py'


class BuildIdentityTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name) / 'source'
        self.root.mkdir()
        self.output = Path(self.directory.name) / 'metadata'
        self.git('init', '--quiet')
        self.git('config', 'user.name', 'Build Identity Test')
        self.git('config', 'user.email', 'build-identity@example.invalid')
        (self.root / 'Package.resolved').write_text(json.dumps({
            'pins': [{'identity': 'dust3d-core', 'state': {'revision': 'b' * 40}}]
        }))
        (self.root / 'source.swift').write_text('let value = 1\n')
        (self.root / '.gitignore').write_text('ignored\n')
        self.git('add', '.')
        self.git('commit', '--quiet', '-m', 'Initial test source')

    def git(self, *arguments):
        return subprocess.check_output(['git', '-C', str(self.root), *arguments], text=True).strip()

    def generate(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), '--root', str(self.root), '--output', str(self.output)],
            capture_output=True, text=True, check=True)
        path = Path(result.stdout.strip())
        return path, json.loads(path.read_text())

    def test_clean_identity_is_deterministic_and_pins_core(self):
        first_path, first = self.generate()
        second_path, second = self.generate()
        self.assertEqual(first, second)
        self.assertEqual(first_path, second_path)
        self.assertEqual(first['sourceRevision'], self.git('rev-parse', 'HEAD'))
        self.assertEqual(first['coreRevision'], 'b' * 40)
        self.assertEqual(first['schemaVersion'], 1)
        self.assertFalse(first['isDirty'])
        self.assertEqual(len(first['sourceDigest']), 64)

    def test_distinct_dirty_source_edits_produce_distinct_link_inputs(self):
        clean_path, clean = self.generate()
        (self.root / 'source.swift').write_text('let value = 2\n')
        first_path, first = self.generate()
        (self.root / 'source.swift').write_text('let value = 3\n')
        second_path, second = self.generate()
        self.assertTrue(first['isDirty'])
        self.assertTrue(second['isDirty'])
        self.assertEqual(first['sourceRevision'], clean['sourceRevision'])
        self.assertEqual(first['sourceRevision'], second['sourceRevision'])
        self.assertEqual(len({clean_path, first_path, second_path}), 3)
        self.assertNotEqual(first['sourceDigest'], second['sourceDigest'])

    def test_untracked_deleted_and_ignored_inputs_are_distinguished(self):
        _, clean = self.generate()
        (self.root / 'ignored').write_text('ignored local output')
        _, ignored = self.generate()
        self.assertEqual(clean, ignored)
        (self.root / 'new.swift').write_text('let extra = true\n')
        _, untracked = self.generate()
        self.assertTrue(untracked['isDirty'])
        self.assertNotEqual(clean['sourceDigest'], untracked['sourceDigest'])
        (self.root / 'source.swift').unlink()
        _, deleted = self.generate()
        self.assertNotEqual(untracked['sourceDigest'], deleted['sourceDigest'])

    def test_missing_git_fails_with_original_cause(self):
        (self.root / ".git").rename(self.root / "original-git")
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root), "--output", str(self.output)],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not a git repository", result.stderr)

    def test_invalid_core_pin_fails_explicitly(self):
        (self.root / 'Package.resolved').write_text('{}')
        result = subprocess.run(
            [sys.executable, str(SCRIPT), '--root', str(self.root), '--output', str(self.output)],
            capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('dust3d-core', result.stderr)


class RunningAppTests(unittest.TestCase):
    def test_should_match_exact_binary_paths_with_spaces(self):
        import importlib.util
        script = SCRIPT.parent / 'check_running_app.py'
        spec = importlib.util.spec_from_file_location('check_running_app', script)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        listing = '  12 /tmp/QA App.app/Contents/MacOS/Dust3DEditor\n13 /tmp/Other.app/Contents/MacOS/Dust3DEditor\n14 /tmp/QA App.app/Contents/MacOS/Dust3DEditorHelper\ninvalid row\n'
        self.assertEqual(module.matching_process_identifiers(
            Path('/tmp/QA App.app/Contents/MacOS/Dust3DEditor'), listing), [12])

    def test_should_normalize_tmp_alias_without_matching_other_apps(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location('check_running_app', SCRIPT.parent / 'check_running_app.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        binary = Path('/tmp/IdentityQA.app/Contents/MacOS/Dust3DEditor')
        listing = '90 ' + str(binary.resolve()) + '\n91 /tmp/Other.app/Contents/MacOS/Dust3DEditor\n'
        self.assertEqual(module.matching_process_identifiers(binary, listing), [90])

    def test_expect_running_mode_checks_the_exact_target(self):
        import importlib.util
        from unittest.mock import patch
        spec = importlib.util.spec_from_file_location('check_running_app', SCRIPT.parent / 'check_running_app.py')
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        binary = '/tmp/ExpectedQA.app/Contents/MacOS/Dust3DEditor'
        for listing, expected in [('71 ' + binary + '\n', 0), ('72 /tmp/Other.app/Contents/MacOS/Dust3DEditor\n', 1)]:
            with patch.object(module.sys, 'argv', ['check_running_app.py', '--expect-running', binary]), \
                    patch.object(module.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, stdout=listing)), \
                    patch.object(module.sys, 'stderr'), patch('builtins.print'):
                self.assertEqual(module.main(), expected)
