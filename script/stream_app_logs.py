#!/usr/bin/env python3
"""Attach an app-scoped live log consumer before launching the selected app."""
import argparse
import math
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time


class LogStreamingError(RuntimeError):
    """The consumer could not attach, the app could not launch, or streaming failed."""


def _stop_consumer(consumer):
    if consumer.poll() is None:
        consumer.terminate()
        try:
            consumer.wait(timeout=2)
        except subprocess.TimeoutExpired:
            consumer.kill()
            consumer.wait(timeout=2)


def stream_application_logs(app_bundle, subsystem, *, logger_command=None, launcher_command=None,
                            output=None, readiness_timeout=10):
    """Forward logs after a live consumer emits its first complete readiness line.

    Launch failures retain their original cause. Only the owned consumer is stopped;
    an application that has launched remains running when capture ends.
    """
    if len(subsystem) > 255 or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', subsystem):
        raise LogStreamingError('Invalid logging subsystem')
    if not math.isfinite(readiness_timeout) or readiness_timeout <= 0:
        raise LogStreamingError('Log readiness timeout must be positive and finite')
    bundle = Path(app_bundle).resolve()
    if not bundle.is_dir():
        raise LogStreamingError(f'App bundle is unavailable: {bundle}')
    logger = list(logger_command if logger_command is not None else ['/usr/bin/log'])
    launcher = list(launcher_command if launcher_command is not None else ['/usr/bin/open'])
    destination = output if output is not None else sys.stdout.buffer
    predicate = f'subsystem == "{subsystem}"'
    try:
        consumer = subprocess.Popen(
            [*logger, 'stream', '--info', '--style', 'compact', '--predicate', predicate],
            stdout=subprocess.PIPE)
    except OSError as cause:
        raise LogStreamingError(f'Cannot start log consumer: {cause}') from cause
    try:
        if consumer.stdout is None:
            raise LogStreamingError('Log consumer has no output channel')
        deadline = time.monotonic() + readiness_timeout
        initial = bytearray()
        with selectors.DefaultSelector() as selector:
            selector.register(consumer.stdout, selectors.EVENT_READ)
            while b'\n' not in initial:
                remaining = deadline - time.monotonic()
                if remaining <= 0 or not selector.select(timeout=remaining):
                    raise LogStreamingError('Log consumer did not become ready before the timeout')
                block = os.read(consumer.stdout.fileno(), 4096)
                if not block:
                    status = consumer.wait(timeout=2)
                    raise LogStreamingError(f'Log consumer ended before readiness (status {status})')
                initial.extend(block)
                destination.write(block)
                destination.flush()
                if len(initial) > 65536:
                    raise LogStreamingError('Log consumer readiness output exceeds its 64 KiB limit')
        if consumer.poll() is not None:
            raise LogStreamingError(f'Log consumer ended before app launch (status {consumer.returncode})')
        try:
            subprocess.run([*launcher, '-n', str(bundle)], check=True, capture_output=True)
        except subprocess.CalledProcessError as cause:
            diagnostic = cause.stderr.decode('utf-8', errors='replace').strip() or str(cause)
            raise LogStreamingError(f'App launch failed: {diagnostic}') from cause
        except OSError as cause:
            raise LogStreamingError(f'App launch failed: {cause}') from cause
        for block in iter(lambda: consumer.stdout.read1(65536), b''):
            destination.write(block)
            destination.flush()
        status = consumer.wait(timeout=2)
        if status != 0:
            raise LogStreamingError(f'Log consumer failed with status {status}')
        return 0
    finally:
        _stop_consumer(consumer)
        if consumer.stdout is not None:
            consumer.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-bundle', type=Path, required=True)
    parser.add_argument('--subsystem', required=True)
    arguments = parser.parse_args()
    try:
        return stream_application_logs(arguments.app_bundle, arguments.subsystem)
    except KeyboardInterrupt:
        return 130
    except (LogStreamingError, OSError, subprocess.SubprocessError) as cause:
        print(f'App log capture failed: {cause}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    sys.exit(main())
