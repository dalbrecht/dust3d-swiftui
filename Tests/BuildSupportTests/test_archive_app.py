"""Archive exactly the signed tree, without synthesizing File Provider metadata files."""
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest
import zipfile

SCRIPT = Path(__file__).resolve().parents[2] / 'script' / 'archive_app.py'


class ArchiveAppTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.bundle = self.root / 'Example App.app'
        self.archive = self.root / 'Example.zip'
        (self.bundle / 'Contents/MacOS').mkdir(parents=True)

    def run_archive(self, output=None, *, env=None):
        return subprocess.run([sys.executable, str(SCRIPT), str(self.bundle), str(output or self.archive)],
                              capture_output=True, text=True, timeout=10, env=env)

    def test_source_date_epoch_makes_archive_independent_of_mtime_and_timezone(self):
        executable = self.bundle / 'Contents/MacOS/Example'
        executable.write_bytes(b'signed executable')
        alias = executable.with_name('Alias')
        alias.symlink_to(executable.name)
        epoch = 1700000001
        env = os.environ | {'SOURCE_DATE_EPOCH': str(epoch), 'TZ': 'UTC0'}
        first = self.run_archive(env=env)
        self.assertEqual(first.returncode, 0, first.stderr)
        original = self.archive.read_bytes()

        for path in [self.bundle, *self.bundle.rglob('*')]:
            os.utime(path, (epoch + 3600, epoch + 3600), follow_symlinks=False)
        second = self.run_archive(env=env | {'TZ': 'EST5'})
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(self.archive.read_bytes(), original)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual({entry.date_time for entry in archive.infolist()}, {time.gmtime(epoch - 1)[:6]})

    def test_malformed_source_date_epoch_preserves_previous_archive(self):
        self.archive.write_bytes(b'previous archive')
        for epoch in ('', '1700000000.5', '1_000', '１２３'):
            with self.subTest(epoch=epoch):
                result = self.run_archive(env=os.environ | {'SOURCE_DATE_EPOCH': epoch})
                self.assertNotEqual(result.returncode, 0)
                self.assertIn('SOURCE_DATE_EPOCH', result.stderr)
                self.assertEqual(self.archive.read_bytes(), b'previous archive')

    def test_regular_signed_bytes_modes_empty_directories_and_literal_sidecar_names_are_preserved(self):
        files = {'Contents/MacOS/Example': b'\0executable\xff',
                 'Contents/Info.plist': b'<plist>signed</plist>',
                 'Contents/Resources/shader.metallib': bytes(range(256)),
                 'Contents/_CodeSignature/CodeResources': b'sealed resources',
                 'Contents/Resources/._legitimate-signed-resource': b'actual signed file'}
        for name, content in files.items():
            path = self.bundle / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
            path.chmod(0o751 if name.endswith('/Example') else 0o640)
        (self.bundle / 'Contents/Resources/Empty').mkdir()
        (self.bundle / 'Contents/Resources/Empty').chmod(0o750)
        result = self.run_archive()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.archive) as archive:
            expected_files = {self.bundle.name + '/' + name for name in files}
            expected_directories = {self.bundle.name + suffix for suffix in ['/', '/Contents/', '/Contents/MacOS/', '/Contents/Resources/', '/Contents/Resources/Empty/', '/Contents/_CodeSignature/']}
            self.assertEqual(set(archive.namelist()), expected_files | expected_directories)
            self.assertEqual({i.filename for i in archive.infolist() if not i.is_dir()}, expected_files)
            for name, content in files.items():
                entry = archive.getinfo(self.bundle.name + '/' + name)
                self.assertEqual(archive.read(entry), content)
                self.assertEqual(entry.create_system, 3)
                self.assertEqual(stat.S_IMODE(entry.external_attr >> 16), 0o751 if name.endswith('/Example') else 0o640)
                self.assertTrue(stat.S_ISREG(entry.external_attr >> 16))
            empty = archive.getinfo(self.bundle.name + '/Contents/Resources/Empty/')
            self.assertTrue(empty.is_dir())
            self.assertEqual(stat.S_IMODE(empty.external_attr >> 16), 0o750)
            self.assertEqual(empty.extra, b'')
            self.assertFalse(any(i.filename.startswith('__MACOSX/') for i in archive.infolist()))

    @unittest.skipUnless(hasattr(os, 'setxattr') or sys.platform == 'darwin', 'Filesystem xattrs are unavailable on this platform')
    def test_attached_filesystem_metadata_creates_no_zip_entries_or_extra_fields(self):
        executable = self.bundle / 'Contents/MacOS/Example'
        executable.write_bytes(b'signed executable')
        attribute = 'com.dust3d.archive-test' if sys.platform == 'darwin' else 'user.dust3d.archive-test'
        if hasattr(os, 'setxattr'):
            os.setxattr(executable, attribute, b'temporary filesystem-only metadata')
        else:
            # Canonical macOS packaging already requires this system utility. Only a disposable
            # fixture file is changed; the helper itself never inspects or copies these attributes.
            subprocess.run(['/usr/bin/xattr', '-w', attribute, 'temporary filesystem-only metadata', str(executable)], check=True)
        result = self.run_archive()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.archive) as archive:
            self.assertEqual(set(archive.namelist()), {self.bundle.name + suffix for suffix in ['/', '/Contents/', '/Contents/MacOS/', '/Contents/MacOS/Example']})
            self.assertTrue(all(entry.extra == b'' for entry in archive.infolist()))
            self.assertEqual(archive.read(self.bundle.name + '/Contents/MacOS/Example'), b'signed executable')

    def test_framework_links_are_encoded_without_dereferencing_including_outside_and_dangling(self):
        framework = self.bundle / 'Contents/Frameworks/Example.framework'
        (framework / 'Versions/A').mkdir(parents=True)
        (framework / 'Versions/A/Example').write_bytes(b'framework binary')
        os.symlink('A', framework / 'Versions/Current')
        os.symlink('Versions/Current/Example', framework / 'Example')
        outside = self.root / 'outside'
        outside.mkdir()
        (outside / 'must-not-read').write_bytes(b'outside secret')
        os.symlink(str(outside), self.bundle / 'Contents/Outside')
        os.symlink('missing-target', self.bundle / 'Contents/Dangling')
        result = self.run_archive()
        self.assertEqual(result.returncode, 0, result.stderr)
        with zipfile.ZipFile(self.archive) as archive:
            for path in [framework / 'Versions/Current', framework / 'Example', self.bundle / 'Contents/Outside', self.bundle / 'Contents/Dangling']:
                entry = archive.getinfo(self.bundle.name + '/' + str(path.relative_to(self.bundle)))
                self.assertTrue(stat.S_ISLNK(entry.external_attr >> 16))
                self.assertEqual(archive.read(entry), os.fsencode(os.readlink(path)))
            self.assertFalse(any('must-not-read' in name for name in archive.namelist()))
            self.assertEqual(sum(name.endswith('/Versions/A/Example') for name in archive.namelist()), 1)

    def test_rejected_special_file_preserves_existing_archive_and_leaves_no_temporary_zip(self):
        self.archive.write_bytes(b'previous archive')
        os.mkfifo(self.bundle / 'Contents/unsupported-fifo')
        result = self.run_archive()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Unsupported bundle entry', result.stderr)
        self.assertEqual(self.archive.read_bytes(), b'previous archive')
        self.assertEqual(sorted(p.name for p in self.root.iterdir()), ['Example App.app', 'Example.zip'])

    def test_output_inside_bundle_is_rejected_before_creating_it(self):
        output = self.bundle / 'Contents/recursive.zip'
        result = self.run_archive(output)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(output.exists())

    def test_bundle_root_symlink_is_rejected(self):
        original = self.bundle
        self.bundle = self.root / 'alias.app'
        self.bundle.symlink_to(original, target_is_directory=True)
        result = self.run_archive()
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.archive.exists())
