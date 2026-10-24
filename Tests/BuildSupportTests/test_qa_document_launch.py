"""Verify isolated QA launch commands without starting any native application."""
import importlib.util
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class QADocumentLaunchTests(unittest.TestCase):
    def setUp(self):
        specification = importlib.util.spec_from_file_location('launch_editor_qa', ROOT / 'script/launch_editor_qa.py')
        self.module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(self.module)
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name)
        self.bundle = self.root / 'QA Editor.app'
        self.contents = self.bundle / 'Contents'
        (self.contents / 'MacOS').mkdir(parents=True)
        self.executable = self.contents / 'MacOS/Dust3DEditor'
        self.executable.write_bytes(b'fixture executable')
        self.executable.chmod(0o755)
        self.metadata = {'CFBundleIdentifier': 'org.dust3d.editor.combine-qa', 'CFBundleExecutable': 'Dust3DEditor'}
        self.write_metadata()
        self.document = self.root / 'Owned model.DS3'
        self.document.write_bytes(b'owned fixture')

    def write_metadata(self):
        (self.contents / 'Info.plist').write_bytes(plistlib.dumps(self.metadata))

    def test_should_preserve_paths_and_isolate_only_the_new_process(self):
        commands = []
        self.module.launch_qa_document(self.bundle, self.document, run=lambda command, **options: commands.append((command, options)))
        self.assertEqual(commands, [([
            '/usr/bin/open', '-n', str(self.bundle), '--args', '-ApplePersistenceIgnoreState', 'YES',
            '--open-document', str(self.document)], {'check': True})])
        self.assertEqual(self.document.read_bytes(), b'owned fixture')

    def test_should_reject_production_bundle_before_launch(self):
        self.metadata['CFBundleIdentifier'] = 'org.dust3d.editor'
        self.write_metadata()
        self.assert_rejected(self.bundle, self.document)

    def assert_rejected(self, bundle, document):
        with self.assertRaises(self.module.QALaunchError):
            self.module.launch_qa_document(bundle, document, run=lambda *args, **kwargs: self.fail('Invalid launch executed'))

    def test_should_reject_missing_relative_directory_and_wrong_extension_documents(self):
        for document in [Path('relative.ds3'), self.root / 'missing.ds3', self.root, self.root / 'model.txt']:
            self.assert_rejected(self.bundle, document)

    def test_should_reject_relative_missing_and_invalid_bundles(self):
        for bundle in [Path('relative.app'), self.root / 'missing.app', self.document]:
            self.assert_rejected(bundle, self.document)
        (self.contents / 'Info.plist').write_bytes(b'invalid plist')
        self.assert_rejected(self.bundle, self.document)

    def test_should_reject_unexpected_or_missing_executable(self):
        self.metadata['CFBundleExecutable'] = '../outside'
        self.write_metadata()
        self.assert_rejected(self.bundle, self.document)
        self.metadata['CFBundleExecutable'] = 'Dust3DEditor'
        self.write_metadata()
        self.executable.unlink()
        self.assert_rejected(self.bundle, self.document)

    def test_should_preserve_launch_failure_cause(self):
        failure = subprocess.CalledProcessError(1, ['/usr/bin/open'])
        def fail(command, **options):
            raise failure
        with self.assertRaises(self.module.QALaunchError) as caught:
            self.module.launch_qa_document(self.bundle, self.document, run=fail)
        self.assertIs(caught.exception.__cause__, failure)

    def test_should_reject_invalid_paths_before_filesystem_lookup(self):
        for path in [Path('/tmp/a\0.ds3'), Path('/' + 'x' * 4096 + '.ds3')]:
            self.assert_rejected(self.bundle, path)
            self.assert_rejected(path, self.document)

    def test_should_reject_non_dictionary_metadata_and_nonexecutable_binary(self):
        (self.contents / 'Info.plist').write_bytes(plistlib.dumps(['not a bundle']))
        self.assert_rejected(self.bundle, self.document)
        self.write_metadata()
        self.executable.chmod(0o644)
        self.assert_rejected(self.bundle, self.document)

    def test_should_return_cli_error_without_launching_for_invalid_bundle(self):
        result = subprocess.run([
            sys.executable, '-B', str(ROOT / 'script/launch_editor_qa.py'),
            '--app-bundle', str(self.root / 'missing.app'), '--document', str(self.document)],
            capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertIn('absolute existing QA .app', result.stderr)
