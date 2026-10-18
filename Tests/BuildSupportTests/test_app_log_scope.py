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
            open_stub.write_text('#!/usr/bin/env bash\nexit 0\n')
            log_stub = tools / 'stream-log'
            log_stub.write_text('''#!/usr/bin/env python3
import json,os,pathlib,sys
pathlib.Path(os.environ['LOG_SCOPE_TEST_RECORDING']).write_text(json.dumps(sys.argv[1:]))
''')
            for tool in [open_stub, log_stub]:
                tool.chmod(0o755)
            # Only native side-effect executables are replaced; app/mode/predicate dispatch stays unchanged.
            script = (ROOT / 'script/build_and_run.sh').read_text()
            self.assertIn('/usr/bin/open', script)
            self.assertIn('/usr/bin/log', script)
            script = script.replace('/usr/bin/open', shlex.quote(str(open_stub)))
            script = script.replace('/usr/bin/log', shlex.quote(str(log_stub)))
            (scripts / 'build_and_run.sh').write_text(script)
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
                               LOG_SCOPE_TEST_RECORDING=str(recording))
            result = subprocess.run(['bash', str(scripts / 'build_and_run.sh'), *app_arguments, '--logs'],
                                    cwd=source, env=environment, capture_output=True, text=True, timeout=30)
            self.assertEqual(result.returncode, 0, result.stderr)
            arguments = json.loads(recording.read_text())
            self.assertIn('--predicate', arguments)
            return arguments[arguments.index('--predicate') + 1]

    def test_should_scope_qa_logs_to_the_qa_subsystem(self):
        self.assertEqual(self.run_log_mode(['--editor-qa']), 'subsystem == "org.dust3d.editor.combine-qa"')

    def test_should_scope_canonical_logs_to_the_canonical_subsystem(self):
        self.assertEqual(self.run_log_mode(['--editor']), 'subsystem == "org.dust3d.editor"')

    def test_should_scope_viewer_logs_to_the_viewer_subsystem(self):
        self.assertEqual(self.run_log_mode([]), 'subsystem == "org.dust3d.viewer"')
