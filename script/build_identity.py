#!/usr/bin/env python3
"""Create a content-addressed linker input without writing generated files into source."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def git(root, *arguments):
    """Read Git state with separate arguments and preserve the original failure cause."""
    return subprocess.run(
        ['git', '-C', str(root), *arguments], check=True, capture_output=True).stdout


def source_digest(root):
    """Hash tracked/unignored input identities without following symlinks outside the tree."""
    paths = set(git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0'))
    digest = hashlib.sha256()
    for name in sorted(paths - {b''}):
        digest.update(len(name).to_bytes(8, 'big'))
        digest.update(name)
        path = root / os.fsdecode(name)
        if path.is_symlink():
            content = b'link\0' + os.fsencode(os.readlink(path))
        elif path.is_file():
            file_digest = hashlib.sha256()
            with path.open('rb') as source:
                for block in iter(lambda: source.read(1024 * 1024), b''):
                    file_digest.update(block)
            content = b'file\0' + file_digest.digest()
        elif path.is_dir():
            # Gitlinks have a recorded identity; their contents are not app compilation inputs.
            content = b'gitlink\0' + git(root, 'rev-parse', 'HEAD:' + os.fsdecode(name)).strip()
        else:
            content = b'deleted'
        digest.update(len(content).to_bytes(8, 'big'))
        digest.update(content)
    return digest.hexdigest()


def generate(root, output):
    """Return immutable JSON named by its own digest so changed metadata forces relinking."""
    if output.is_relative_to(root):
        raise ValueError('Build identity output must be outside the source tree')
    revision = git(root, 'rev-parse', 'HEAD').decode('ascii').strip()
    pins = json.loads((root / 'Package.resolved').read_text()).get('pins')
    if not isinstance(pins, list):
        raise ValueError('Package.resolved has no dust3d-core pin list')
    core = [pin.get('state', {}).get('revision') for pin in pins
            if isinstance(pin, dict) and pin.get('identity') == 'dust3d-core']
    if len(core) != 1 or not isinstance(core[0], str) or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', core[0]):
        raise ValueError('Package.resolved must pin exactly one valid dust3d-core revision')
    data = json.dumps({
        'schemaVersion': 1, 'sourceRevision': revision, 'coreRevision': core[0],
        'sourceDigest': source_digest(root),
        'isDirty': bool(git(root, 'status', '--porcelain', '--untracked-files=all', '-z')),
    }, sort_keys=True, separators=(',', ':')).encode('utf-8')
    output.mkdir(parents=True, exist_ok=True)
    path = output / (hashlib.sha256(data).hexdigest() + '.json')
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError('Existing content-addressed build identity has changed')
    else:
        path.write_bytes(data)
    return path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    arguments = parser.parse_args()
    try:
        print(generate(arguments.root.resolve(), arguments.output.resolve()))
    except subprocess.CalledProcessError as error:
        print(error.stderr.decode('utf-8', errors='replace').strip(), file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError) as error:
        print(f'Build identity unavailable: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
