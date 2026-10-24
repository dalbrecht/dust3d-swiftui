#!/usr/bin/env python3
"""Launch the existing QA identity with one explicit fixture and isolated restoration."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import sys


class QALaunchError(RuntimeError):
    """QA launch validation or Launch Services failed, retaining the original cause."""


def launch_qa_document(app_bundle, document, *, run=subprocess.run):
    """Validate a QA bundle and fixture, then launch through Launch Services.

    Both paths must be absolute. The caller must own the fixture and verify build
    provenance before calling. This does not attest to document contents, inspect
    other processes, or prove the resulting window count. Raises QALaunchError on
    validation or launch failure. The injected runner receives a list, never shell
    text. No defaults, saved state, source documents or existing bundles are edited.
    """
    bundle = Path(app_bundle)
    fixture = Path(document)
    for path in [bundle, fixture]:
        if '\0' in str(path) or len(str(path).encode('utf-8')) > 4096:
            raise QALaunchError('Launch paths must contain no NUL and at most 4096 UTF-8 bytes')
    if not bundle.is_absolute() or bundle.suffix != '.app' or not bundle.is_dir():
        raise QALaunchError('Use an absolute existing QA .app bundle path')
    if not fixture.is_absolute() or fixture.suffix.lower() != '.ds3' or not fixture.is_file():
        raise QALaunchError('Use an absolute existing owned .ds3 fixture path')
    try:
        with (bundle / 'Contents/Info.plist').open('rb') as source:
            metadata = plistlib.load(source)
    except (OSError, ValueError, plistlib.InvalidFileException) as cause:
        raise QALaunchError(f'Cannot read QA bundle metadata: {cause}') from cause
    if not isinstance(metadata, dict) or metadata.get('CFBundleIdentifier') != 'org.dust3d.editor.combine-qa':
        raise QALaunchError('The bundle must use the existing editor QA identity')
    if metadata.get('CFBundleExecutable') != 'Dust3DEditor':
        raise QALaunchError('The QA bundle must contain the Dust3DEditor executable')
    executable = bundle / 'Contents/MacOS/Dust3DEditor'
    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise QALaunchError('The QA editor executable is missing or not executable')
    # Apple's AppKit testing default redirects new state to temporary storage.
    # Pass it in this process's argument domain; never persist it with defaults write.
    command = ['/usr/bin/open', '-n', str(bundle), '--args', '-ApplePersistenceIgnoreState', 'YES',
               '--open-document', str(fixture)]
    try:
        run(command, check=True)
    except (OSError, subprocess.SubprocessError) as cause:
        raise QALaunchError(f'QA app launch failed: {cause}') from cause


def main():
    """Parse explicit paths; return a nonzero status with the validation/launch cause."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app-bundle', required=True, type=Path)
    parser.add_argument('--document', required=True, type=Path)
    arguments = parser.parse_args()
    try:
        launch_qa_document(arguments.app_bundle, arguments.document)
    except QALaunchError as cause:
        print(str(cause), file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
