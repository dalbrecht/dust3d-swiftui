"""Exercise log-consumer readiness and cleanup without launching native applications."""
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class AppLogStreamTests(unittest.TestCase):
    def setUp(self):
        specification = importlib.util.spec_from_file_location('stream_app_logs', ROOT / 'script/stream_app_logs.py')
        self.module = importlib.util.module_from_spec(specification)
        specification.loader.exec_module(self.module)
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.app = self.root / 'Fixture.app'
        self.app.mkdir()
        self.launched = self.root / 'launched'
        self.launch_command = [sys.executable, '-c', 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("launched")', str(self.launched)]

    def stream(self, logger, launcher=None, subsystem='org.example.qa', timeout=2):
        return self.module.stream_application_logs(
            self.app, subsystem, logger_command=[sys.executable, '-u', '-c', logger],
            launcher_command=launcher or self.launch_command, output=io.BytesIO(), readiness_timeout=timeout)

    def test_should_not_launch_when_the_consumer_never_becomes_ready(self):
        with self.assertRaisesRegex(self.module.LogStreamingError, 'ready'):
            self.stream('import time; time.sleep(5)', timeout=0.05)
        self.assertFalse(self.launched.exists())

    def test_should_preserve_early_consumer_failure_status(self):
        with self.assertRaisesRegex(self.module.LogStreamingError, '17'):
            self.stream('import sys; sys.exit(17)')
        self.assertFalse(self.launched.exists())

    def test_should_reject_even_successful_consumer_exit_before_readiness(self):
        with self.assertRaisesRegex(self.module.LogStreamingError, 'before'):
            self.stream('import sys; sys.exit(0)')
        self.assertFalse(self.launched.exists())

    def test_should_preserve_launch_failure_and_stop_the_consumer(self):
        launcher = [sys.executable, '-c', 'import sys; sys.stderr.write("launch fixture failure"); sys.exit(24)']
        with self.assertRaisesRegex(self.module.LogStreamingError, 'launch fixture failure'):
            self.stream('import time; print("ready", flush=True); time.sleep(5)', launcher=launcher)

    def test_should_reject_invalid_scope_before_starting_processes(self):
        with self.assertRaisesRegex(self.module.LogStreamingError, 'subsystem'):
            self.stream('print("ready", flush=True)', subsystem='org.example" OR TRUEPREDICATE')
        self.assertFalse(self.launched.exists())
