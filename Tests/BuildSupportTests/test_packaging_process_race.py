"""A target launched during compilation must not have its running bundle replaced."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class PackagingProcessRaceTests(unittest.TestCase):
    def run_scenario(self, arguments, application_name, launch_during_product=None, fail_during_product=None):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            root = temporary / 'source'
            scripts = root / 'script'
            scripts.mkdir(parents=True)
            for name in ['build_and_run.sh', 'build_paths.sh', 'package_file_preview_extensions.sh']:
                shutil.copyfile(ROOT / 'script' / name, scripts / name)
            marker = temporary / 'target-started'
            (scripts / 'check_running_app.py').write_text('''import os, pathlib, sys
if pathlib.Path(os.environ['PACKAGING_TEST_RUNNING_MARKER']).exists():
    print('Target launched while the build was running', file=sys.stderr)
    sys.exit(1)
''')
            build = scripts / 'swift.sh'
            build.write_text('''#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/build_paths.sh"
mkdir -p "$DUST3D_BINARY_DIR/Dust3DNative_Dust3DRendering.bundle"
printf '%s' 'replacement binary' > "$DUST3D_BINARY_DIR/$3"
if [ "$3" = "$PACKAGING_TEST_LAUNCH_PRODUCT" ]; then touch "$PACKAGING_TEST_RUNNING_MARKER"; fi
if [ "$3" = "$PACKAGING_TEST_FAIL_PRODUCT" ]; then echo "Provider compilation fixture failure" >&2; exit 23; fi
''')
            build.chmod(0o755)
            tools = temporary / 'tools'
            tools.mkdir()
            for name in ['codesign', 'xattr', 'ditto']:
                tool = tools / name
                tool.write_text('#!/usr/bin/env bash\nexit 0\n')
                tool.chmod(0o755)
            checker = scripts / 'check_file_preview_bundles.sh'
            checker.write_text('#!/usr/bin/env bash\nexit 0\n')
            checker.chmod(0o755)
            (scripts / 'package_file_preview_extensions.sh').chmod(0o755)
            icons = root / 'assets/app-icons'
            icons.mkdir(parents=True)
            (icons / (application_name + '.icns')).write_bytes(b'icns-fixture')
            output = temporary / 'apps'
            bundle = output / (application_name + '.app')
            executable = bundle / 'Contents/MacOS' / application_name
            executable.parent.mkdir(parents=True)
            executable.write_bytes(b'original running binary')
            environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'], DUST3D_BUILD_ROOT=str(temporary / 'cache'),
                               DUST3D_APP_OUTPUT_DIR=str(output),
                               DUST3D_ARCHIVE_OUTPUT_DIR=str(temporary / 'archives'),
                               PACKAGING_TEST_RUNNING_MARKER=str(marker),
                               PACKAGING_TEST_LAUNCH_PRODUCT=launch_during_product or application_name,
                               PACKAGING_TEST_FAIL_PRODUCT=fail_during_product or "")
            result = subprocess.run(['bash', str(scripts / 'build_and_run.sh'), *arguments], cwd=root,
                                    env=environment, capture_output=True, text=True, timeout=30)
            self.assertTrue(marker.exists(), 'The simulated build did not run')
            self.assertEqual(executable.read_bytes(), b'original running binary',
                             'Packaging replaced a target that started during compilation')
            self.assertNotEqual(result.returncode, 0)
            diagnostic = 'Provider compilation fixture failure' if fail_during_product else 'Target launched while the build was running'
            self.assertIn(diagnostic, result.stderr)
            self.assertFalse((bundle / 'Contents/Info.plist').exists())

    def test_should_recheck_qa_editor_after_build_before_copying(self):
        self.run_scenario(['--editor-qa', '--build-only'], 'Dust3DEditor')

    def test_should_recheck_canonical_editor_after_build_before_copying(self):
        self.run_scenario(['--editor', '--build-only'], 'Dust3DEditor')

    def test_should_recheck_viewer_after_build_before_copying(self):
        self.run_scenario(['--build-only'], 'Dust3DViewer')

    def test_should_build_quicklook_before_the_final_process_check(self):
        self.run_scenario(['--editor', '--build-only'], 'Dust3DEditor', 'Dust3DQuickLookExtension')

    def test_should_build_thumbnails_before_the_final_process_check(self):
        self.run_scenario(['--editor', '--build-only'], 'Dust3DEditor', 'Dust3DThumbnailExtension')

    def test_should_keep_the_existing_bundle_when_quicklook_compilation_fails(self):
        self.run_scenario(['--editor', '--build-only'], 'Dust3DEditor', 'Dust3DQuickLookExtension', 'Dust3DQuickLookExtension')

    def test_should_keep_the_existing_bundle_when_thumbnail_compilation_fails(self):
        self.run_scenario(['--editor', '--build-only'], 'Dust3DEditor', 'Dust3DThumbnailExtension', 'Dust3DThumbnailExtension')
