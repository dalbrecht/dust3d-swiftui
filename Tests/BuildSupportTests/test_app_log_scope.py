"""Verify real packaging-mode dispatch without launching native windows or system log streams."""
import json
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AppLogScopeTests(unittest.TestCase):
    def run_log_mode(self, app_arguments):
        with tempfile.TemporaryDirectory() as directory:
            temporary = Path(directory)
            source = temporary / 'source'
            scripts = source / 'script'
            scripts.mkdir(parents=True)
            tools = temporary / 'tools'
            tools.mkdir()
            recording = temporary / 'log-arguments.json'
            open_stub = tools / 'open-app'
            open_stub.write_text('''#!/usr/bin/env python3
import os,pathlib,sys
if not pathlib.Path(os.environ['LOG_SCOPE_TEST_RECORDING']).exists():
    print('Consumer was not attached before app launch', file=sys.stderr)
    sys.exit(25)
pathlib.Path(os.environ['LOG_SCOPE_TEST_LAUNCHED']).write_text('appStartup fixture')
''')
            log_stub = tools / 'stream-log'
            log_stub.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys,time
pathlib.Path(os.environ['LOG_SCOPE_TEST_RECORDING']).write_text(json.dumps(sys.argv[1:]))
print('stream-ready', flush=True)
launch = pathlib.Path(os.environ['LOG_SCOPE_TEST_LAUNCHED'])
deadline = time.monotonic() + 5
while not launch.exists() and time.monotonic() < deadline:
    time.sleep(0.01)
if not launch.exists(): sys.exit(29)
print(launch.read_text(), flush=True)
''')
            for tool in [open_stub, log_stub]:
                tool.chmod(0o755)
            # Only native side-effect executables are replaced; app/mode/predicate dispatch stays unchanged.
            script = (ROOT / 'script/build_and_run.sh').read_text()
            self.assertIn('/usr/bin/open', script)
            script = script.replace('/usr/bin/open', shlex.quote(str(open_stub)))
            (scripts / 'build_and_run.sh').write_text(script)
            supervisor = (ROOT / 'script/stream_app_logs.py').read_text()
            self.assertIn("'/usr/bin/log'", supervisor)
            supervisor = supervisor.replace("'/usr/bin/log'", repr(str(log_stub)))
            supervisor = supervisor.replace("'/usr/bin/open'", repr(str(open_stub)))
            (scripts / 'stream_app_logs.py').write_text(supervisor)
            shutil.copyfile(ROOT / 'script/build_paths.sh', scripts / 'build_paths.sh')
            (scripts / 'check_running_app.py').write_text('import sys\nsys.exit(0)\n')
            for name in ['package_file_preview_extensions.sh', 'check_file_preview_bundles.sh']:
                path = scripts / name
                path.write_text('#!/usr/bin/env bash\nexit 0\n')
                path.chmod(0o755)
            build = scripts / 'swift.sh'
            build.write_text('''#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/build_paths.sh"
mkdir -p "$DUST3D_BINARY_DIR/Dust3DNative_Dust3DRendering.bundle"
printf '%s' 'fixture binary' > "$DUST3D_BINARY_DIR/Dust3DEditor"
printf '%s' 'fixture binary' > "$DUST3D_BINARY_DIR/Dust3DViewer"
''')
            build.chmod(0o755)
            for name in ['codesign', 'xattr', 'ditto']:
                tool = tools / name
                tool.write_text('#!/usr/bin/env bash\nexit 0\n')
                tool.chmod(0o755)
            icons = source / 'assets/app-icons'
            icons.mkdir(parents=True)
            for name in ['Dust3DEditor', 'Dust3DViewer']:
                (icons / (name + '.icns')).write_bytes(b'icns-fixture')
            environment = dict(os.environ, PATH=str(tools) + os.pathsep + os.environ['PATH'],
                               DUST3D_BUILD_ROOT=str(temporary / 'cache'),
                               DUST3D_APP_OUTPUT_DIR=str(temporary / 'apps'),
                               DUST3D_ARCHIVE_OUTPUT_DIR=str(temporary / 'archives'),
                               LOG_SCOPE_TEST_RECORDING=str(recording),
                               LOG_SCOPE_TEST_LAUNCHED=str(temporary / "launched"))
            result = subprocess.run(['bash', str(scripts / 'build_and_run.sh'), *app_arguments, '--logs'],
                                    cwd=source, env=environment, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn('appStartup fixture', result.stdout)
            arguments = json.loads(recording.read_text())
            self.assertIn('--predicate', arguments)
            return arguments[arguments.index('--predicate') + 1]

    def test_should_scope_qa_logs_to_the_qa_subsystem(self):
        self.assert_scope(self.run_log_mode(['--editor-qa']), 'org.dust3d.editor.combine-qa', 'Dust3DEditor')

    def test_should_scope_canonical_logs_to_the_canonical_subsystem(self):
        self.assert_scope(self.run_log_mode(['--editor']), 'org.dust3d.editor', 'Dust3DEditor')

    def test_should_scope_viewer_logs_to_the_viewer_subsystem(self):
        self.assert_scope(self.run_log_mode([]), 'org.dust3d.viewer', 'Dust3DViewer')

    def assert_scope(self, predicate, subsystem, executable):
        prefix = f'subsystem == "{subsystem}" AND processImagePath == '
        self.assertTrue(predicate.startswith(prefix), predicate)
        path = Path(json.loads(predicate[len(prefix):]))
        self.assertTrue(path.is_absolute())
        self.assertEqual(path.parts[-4:], (executable + '.app', 'Contents', 'MacOS', executable))

    def test_should_distinguish_staged_copies_with_the_same_bundle_identifier(self):
        first = self.run_log_mode(['--editor'])
        second = self.run_log_mode(['--editor'])
        self.assert_scope(first, 'org.dust3d.editor', 'Dust3DEditor')
        self.assert_scope(second, 'org.dust3d.editor', 'Dust3DEditor')
        self.assertNotEqual(first, second)
