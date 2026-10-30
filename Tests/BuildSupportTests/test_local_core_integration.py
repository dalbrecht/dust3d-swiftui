"""Contracts for isolated local-core builds."""
import importlib.util
import json
from pathlib import Path
import tempfile
import sys
import unittest

SCRIPT = Path(__file__).resolve().parents[2] / 'script' / 'local_core_integration.py'
sys.path.insert(0, str(SCRIPT.parent))
spec = importlib.util.spec_from_file_location('local_core_integration', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class LocalCoreIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.resolved = self.root / 'Package.resolved'
        self.snapshot = self.root / 'snapshot'
        self.resolved.write_bytes(b'{"pins":[{"identity":"dust3d-core","state":{"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]}\n')
        module.save_resolved(self.resolved, self.snapshot)

    def test_invalid_pin_is_rejected_before_snapshot(self):
        for state in [None, [], "bad"]:
            self.resolved.write_text(json.dumps({"pins": [{"identity": "dust3d-core", "state": state}]}))
            with self.assertRaisesRegex(ValueError, 'dust3d-core'):
                module.save_resolved(self.resolved, self.root / 'invalid')

    def test_missing_resolved_is_restored_exactly(self):
        self.resolved.unlink()
        module.restore_resolved(self.resolved, self.snapshot)
        self.assertEqual(self.resolved.read_bytes(), b'{"pins":[{"identity":"dust3d-core","state":{"revision":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}}]}\n')

    def test_changed_resolved_and_corrupt_snapshot_are_rejected(self):
        self.resolved.write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'changed'):
            module.restore_resolved(self.resolved, self.snapshot)
        self.resolved.unlink()
        self.snapshot.write_bytes(b'corrupt')
        with self.assertRaisesRegex(ValueError, 'corrupt'):
            module.restore_resolved(self.resolved, self.snapshot)
        self.assertFalse(self.resolved.exists())

    def test_selection_requires_one_edited_dependency_at_exact_path(self):
        state = self.root / 'workspace-state.json'
        core = self.root / 'core'
        core.mkdir()
        def write(path, name='edited'):
            state.write_text(json.dumps({'object': {'dependencies': [{'packageRef': {'identity': 'dust3d-core'}, 'state': {'name': name, 'path': str(path)}}]}}))
        write(core)
        module.verify_selection(state, core)
        write(self.root / 'other')
        with self.assertRaisesRegex(ValueError, 'selected'):
            module.verify_selection(state, core)
        write(core, 'sourceControlCheckout')
        with self.assertRaisesRegex(ValueError, 'selected'):
            module.verify_selection(state, core)

    def test_snapshot_comparison_rejects_changed_copied_file(self):
        source = self.root / 'source'
        target = self.root / 'copy'
        source.mkdir()
        target.mkdir()
        (source / 'input').write_text('original')
        (target / 'input').write_text('original')
        module.verify_snapshot(source, target, [b'input'])
        (target / 'input').write_text('changed')
        with self.assertRaisesRegex(ValueError, 'snapshot'):
            module.verify_snapshot(source, target, [b'input'])

    def test_cli_rejects_path_or_cache_overrides(self):
        for args in [['build', '--package-path=/tmp/other'], ['build', '--chdir', '/tmp'],
                     ['test', '--scratch-path=/tmp/cache'], ['build', '-Xlinker', 'evil']]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                module.validate_arguments(args)
        module.validate_arguments(['test', '--filter', 'ExampleTests'])

    def test_gitlink_directory_is_a_non_compiled_input(self):
        from unittest.mock import patch
        source, target = self.root / 'source', self.root / 'copy'
        source.mkdir()
        (source / '.standards').mkdir()
        (source / '.standards' / 'ignored').write_text('not compiled')
        with patch.object(module.build_identity, 'git', return_value=b'.standards\0'):
            module.copy_source(source, target, {b'.standards': b'a' * 40})
        self.assertTrue((target / '.standards').is_dir())
        self.assertEqual(list((target / '.standards').iterdir()), [])
        module.verify_snapshot(source, target, [b'.standards'], {b'.standards': b'a' * 40})
        with self.assertRaises(ValueError):
            module.verify_snapshot(source, target, [b'.standards'], {})

    def test_failed_command_runs_validation_and_preserves_command_status(self):
        import subprocess
        calls = []
        def fail():
            raise subprocess.CalledProcessError(23, ['swift'])
        def validate():
            calls.append('validated')
            raise ValueError('snapshot changed')
        with self.assertRaises(subprocess.CalledProcessError) as failure:
            module.run_guarded(fail, validate)
        self.assertEqual(failure.exception.returncode, 23)
        self.assertEqual(calls, ['validated'])

    def test_selected_package_link_must_target_core(self):
        core = self.root / 'core'
        core.mkdir()
        link = self.root / 'link'
        link.symlink_to(core)
        module.verify_package_link(link, core)
        link.unlink()
        link.symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, 'selected'):
            module.verify_package_link(link, core)

    def test_absolute_internal_symlink_cannot_write_through_snapshot(self):
        from unittest.mock import patch
        source, target = self.root / 'source', self.root / 'copy'
        source.mkdir()
        (source / 'original').write_text('safe')
        (source / 'link').symlink_to(source / 'original')
        with patch.object(module.build_identity, 'git', return_value=b'link\0original\0'):
            with self.assertRaisesRegex(ValueError, 'Absolute'):
                module.copy_source(source, target, {})
        self.assertEqual((source / 'original').read_text(), 'safe')
        self.assertFalse((target / 'link').is_symlink())

    def test_corrupt_workspace_state_fails_closed(self):
        state = self.root / 'workspace-state.json'
        state.write_text('{}')
        with self.assertRaises(ValueError):
            module.verify_selection(state, self.root)
