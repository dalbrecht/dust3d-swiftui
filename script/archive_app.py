#!/usr/bin/env python3
"""Archive an app tree without synthesizing xattr or AppleDouble metadata files."""
import argparse
import os
from pathlib import Path
import shutil
import stat
import tempfile
import time
import zipfile


class ArchiveError(ValueError):
    """The input tree cannot be represented faithfully by this app archive."""


def _info(name, status):
    timestamp = time.localtime(status.st_mtime)[:6]
    if timestamp[0] < 1980:
        timestamp = (1980, 1, 1, 0, 0, 0)
    elif timestamp[0] > 2107:
        timestamp = (2107, 12, 31, 23, 59, 58)
    info = zipfile.ZipInfo(name, timestamp)
    info.create_system = 3
    info.external_attr = status.st_mode << 16
    if stat.S_ISDIR(status.st_mode):
        info.external_attr |= 0x10
    else:
        info.compress_type = zipfile.ZIP_DEFLATED
    return info


def _write_tree(archive, path, name):
    status = path.lstat()
    if stat.S_ISLNK(status.st_mode):
        # Store the link itself, including dangling or external targets. Never read its referent.
        archive.writestr(_info(name, status), os.fsencode(os.readlink(path)))
    elif stat.S_ISDIR(status.st_mode):
        archive.writestr(_info(name + '/', status), b'')
        with os.scandir(path) as entries:
            children = sorted(entries, key=lambda entry: os.fsencode(entry.name))
        for child in children:
            _write_tree(archive, path / child.name, name + '/' + child.name)
    elif stat.S_ISREG(status.st_mode):
        with path.open('rb') as source, archive.open(_info(name, status), 'w', force_zip64=True) as target:
            shutil.copyfileobj(source, target)
    else:
        raise ArchiveError(f'Unsupported bundle entry: {path}')


def archive_app(bundle, output):
    """Atomically replace output with an exact parent-preserving UNIX ZIP of bundle.

    Args: bundle is a real directory; output is outside it. No symlinks are followed
    within the bundle, and no filename patterns are omitted. Filesystem-only metadata
    is not enumerated. Raises ArchiveError/OSError on invalid or unreadable entries,
    preserving an existing output archive. Example: archive_app(Path('Editor.app'), Path('Editor.zip')).
    """
    bundle, output = Path(bundle).absolute(), Path(output).absolute()
    if not bundle.name or not stat.S_ISDIR(bundle.lstat().st_mode):
        raise ArchiveError('Bundle root must be a real directory')
    if output.resolve().is_relative_to(bundle.resolve()):
        raise ArchiveError('Archive destination must be outside the bundle')
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(prefix='.' + output.name + '.', suffix='.tmp', dir=output.parent, delete=False) as file:
            temporary = Path(file.name)
        with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED) as archive:
            _write_tree(archive, bundle, bundle.name)
        os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle', type=Path)
    parser.add_argument('output', type=Path)
    arguments = parser.parse_args()
    try:
        archive_app(arguments.bundle, arguments.output)
    except (ArchiveError, OSError) as error:
        parser.exit(1, f'{error}\n')


if __name__ == '__main__':
    main()
