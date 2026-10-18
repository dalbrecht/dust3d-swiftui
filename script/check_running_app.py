#!/usr/bin/env python3
"""Refuse to replace the exact running app bundle without affecting other QA identities."""
from pathlib import Path
import subprocess
import sys


def matching_process_identifiers(binary, listing):
    """Match executable paths, preserving spaces and normalizing filesystem aliases."""
    expected = binary.resolve()
    matches = []
    for line in listing.splitlines():
        fields = line.strip().split(maxsplit=1)
        if len(fields) == 2 and fields[0].isdigit() and Path(fields[1]).resolve() == expected:
            matches.append(int(fields[0]))
    return matches


def main():
    arguments = sys.argv[1:]
    expects_running = arguments[:1] == ['--expect-running']
    if expects_running:
        arguments = arguments[1:]
    if len(arguments) != 1:
        print('Usage: check_running_app.py [--expect-running] APP_EXECUTABLE', file=sys.stderr)
        return 2
    try:
        listing = subprocess.run(
            ['ps', '-axo', 'pid=,comm='], check=True, capture_output=True, text=True).stdout
        matches = matching_process_identifiers(Path(arguments[0]), listing)
    except (OSError, subprocess.CalledProcessError) as error:
        cause = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f'Cannot verify whether the target app is running: {cause}', file=sys.stderr)
        return 2
    if expects_running:
        if matches:
            print(f'Verified target app process IDs: {matches}')
            return 0
        print('The target app executable is not running.', file=sys.stderr)
        return 1
    if matches:
        print('Quit the target app normally before rebuilding; pending document edits may need saving. '
              f'Running process IDs: {matches}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
