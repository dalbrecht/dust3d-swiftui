#!/usr/bin/env python3
"""Build an isolated app snapshot against a local editable dust3d-core checkout."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import build_identity


def save_resolved(path, snapshot):
    data = path.read_bytes()
    payload = json.loads(data)
    pins = payload.get('pins') if isinstance(payload, dict) else None
    matches = [pin.get('state') for pin in pins
               if isinstance(pin, dict) and pin.get('identity') == 'dust3d-core'] if isinstance(pins, list) else []
    matches = [state.get('revision') if isinstance(state, dict) else None for state in matches]
    if len(matches) != 1 or not isinstance(matches[0], str) or not re.fullmatch(r'[0-9a-f]{40}|[0-9a-f]{64}', matches[0]):
        raise ValueError('Package.resolved must pin exactly one valid dust3d-core revision')
    snapshot.write_bytes(data)
    snapshot.with_suffix('.sha256').write_text(hashlib.sha256(data).hexdigest())


def restore_resolved(path, snapshot):
    data = snapshot.read_bytes()
    if hashlib.sha256(data).hexdigest() != snapshot.with_suffix('.sha256').read_text():
        raise ValueError('Package.resolved snapshot is corrupt')
    json.loads(data)
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError('Package.resolved changed during local integration')
    else:
        path.write_bytes(data)


def verify_selection(state_path, core):
    try:
        dependencies = json.loads(state_path.read_bytes())['object']['dependencies']
        matches = [item for item in dependencies if item['packageRef']['identity'] == 'dust3d-core']
        if len(matches) != 1 or matches[0]['state']['name'] != 'edited' or Path(matches[0]['state']['path']).resolve() != core.resolve():
            raise ValueError('SwiftPM selected a different core dependency')
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise ValueError('Invalid SwiftPM workspace state') from error


def verify_package_link(link, core):
    if not link.is_symlink() or link.resolve() != core.resolve():
        raise ValueError('SwiftPM selected a different core package link')


def identity(root):
    return {'revision': build_identity.git(root, 'rev-parse', 'HEAD').decode().strip(),
            'digest': build_identity.source_digest(root),
            'dirty': bool(build_identity.git(root, 'status', '--porcelain', '--untracked-files=all', '-z'))}


def indexed_gitlinks(root):
    result = {}
    for entry in build_identity.git(root, 'ls-files', '--stage', '-z').split(b'\0'):
        if not entry:
            continue
        fields, name = entry.split(b'\t', 1)
        mode, revision, stage = fields.split(b' ')
        if mode == b'160000':
            if stage != b'0' or name in result:
                raise ValueError('Unmerged gitlink is unsupported')
            result[name] = revision
    return result


def copy_source(root, destination, gitlinks):
    destination.mkdir()
    names = build_identity.git(root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0')
    for name in sorted(set(names) - {b''}):
        relative = Path(os.fsdecode(name))
        source = root / relative
        target = destination / relative
        if name in gitlinks:
            if source.is_symlink() or (source.exists() and not source.is_dir()):
                raise ValueError(f'Invalid gitlink: {relative}')
            target.mkdir(parents=True, exist_ok=True)
        elif source.is_symlink():
            if os.path.isabs(os.readlink(source)):
                raise ValueError(f'Absolute source symlink is unsupported: {relative}')
            resolved = source.resolve()
            if not resolved.is_relative_to(root):
                raise ValueError(f'Source symlink escapes checkout: {relative}')
            target.parent.mkdir(parents=True, exist_ok=True)
            target.symlink_to(os.readlink(source))
        elif source.is_file():
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, target)
        elif source.exists():
            raise ValueError(f'Unsupported source input: {relative}')


def verify_snapshot(source, target, names, gitlinks=None):
    gitlinks = gitlinks or {}
    for name in names:
        relative = Path(os.fsdecode(name))
        original, copied = source / relative, target / relative
        if name in gitlinks:
            valid = copied.is_dir() and not copied.is_symlink() and not any(copied.iterdir())
        elif original.is_symlink():
            valid = copied.is_symlink() and os.readlink(original) == os.readlink(copied)
        elif original.is_file():
            valid = copied.is_file() and not copied.is_symlink() and original.stat().st_mode == copied.stat().st_mode
            if valid:
                with original.open('rb') as first, copied.open('rb') as second:
                    while True:
                        block = first.read(1024 * 1024)
                        if block != second.read(1024 * 1024):
                            valid = False
                            break
                        if not block:
                            break
        elif original.is_dir():
            valid = False
        else:
            valid = not copied.exists() and not copied.is_symlink()
        if not valid:
            raise ValueError(f'App snapshot changed: {relative}')


def validate_arguments(arguments):
    if not arguments or arguments[0] not in ('build', 'test'):
        raise ValueError('Only SwiftPM build and test are supported')
    value_options = {'--product', '--filter', '--configuration'}
    switches = {'--enable-code-coverage', '--parallel'}
    index = 1
    while index < len(arguments):
        option = arguments[index]
        if option in switches:
            index += 1
        elif option in value_options and index + 1 < len(arguments) and not arguments[index + 1].startswith('-'):
            index += 2
        else:
            raise ValueError(f'Unsupported SwiftPM argument: {option}')


def run_guarded(action, validate):
    try:
        action()
    except Exception:
        try:
            validate()
        except Exception as error:
            print(f'Post-command verification also failed: {error}', file=sys.stderr)
        raise
    validate()


def run(app, core, root, arguments):
    validate_arguments(arguments)
    app, core, root = app.resolve(), core.resolve(), root.resolve()
    if root.is_relative_to(app) or root.is_relative_to(core) or app.is_relative_to(root) or core.is_relative_to(root):
        raise ValueError('Build root and source trees must be disjoint')
    before_app, before_core = identity(app), identity(core)
    root.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix='local-core-', dir=root))
    print(f'Isolated build: {work}', flush=True)
    snapshot_app = work / 'app'
    gitlinks = indexed_gitlinks(app)
    copy_source(app, snapshot_app, gitlinks)
    names = set(build_identity.git(app, 'ls-files', '--cached', '--others', '--exclude-standard', '-z').split(b'\0')) - {b''}
    verify_snapshot(app, snapshot_app, names, gitlinks)
    if identity(app) != before_app or identity(core) != before_core:
        raise ValueError('Source changed while preparing snapshot')
    resolved = snapshot_app / 'Package.resolved'
    saved = work / 'resolved.snapshot'
    save_resolved(resolved, saved)
    scratch = work / 'build'
    options = ['--disable-sandbox', '--scratch-path', str(scratch), '--cache-path', str(work / 'cache'),
               '--config-path', str(work / 'config'), '--security-path', str(work / 'security')]
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(work / 'clang'), SWIFTPM_MODULECACHE_OVERRIDE=str(work / 'modules'), GIT_OPTIONAL_LOCKS='0')
    def swift(*args):
        subprocess.run(['xcrun', 'swift', *args], cwd=snapshot_app, env=env, check=True)
    run_guarded(lambda: swift('package', *options, 'resolve'), lambda: restore_resolved(resolved, saved))
    run_guarded(lambda: swift('package', *options, 'edit', 'dust3d-core', '--path', str(core)),
                lambda: restore_resolved(resolved, saved))
    verify_selection(scratch / 'workspace-state.json', core)
    verify_package_link(snapshot_app / 'Packages/dust3d-core', core)
    subprocess.run([sys.executable, str(snapshot_app / 'script/glb_catalog_quarantine.py'), '--core', str(core)], check=True)
    data = {'schemaVersion': 1, 'sourceRevision': before_app['revision'], 'sourceDigest': before_app['digest'],
            'isDirty': before_app['dirty'], 'coreRevision': before_core['revision'],
            'coreDigest': before_core['digest'], 'coreIsDirty': before_core['dirty']}
    metadata = work / 'identity.json'
    metadata_bytes = json.dumps(data, sort_keys=True, separators=(',', ':')).encode()
    metadata.write_bytes(metadata_bytes)
    def validate_after_build():
        restore_resolved(resolved, saved)
        verify_selection(scratch / 'workspace-state.json', core)
        verify_package_link(snapshot_app / 'Packages/dust3d-core', core)
        verify_snapshot(app, snapshot_app, names, gitlinks)
        if metadata.read_bytes() != metadata_bytes:
            raise ValueError('Build identity changed during SwiftPM execution')
        if indexed_gitlinks(app) != gitlinks or identity(app) != before_app or identity(core) != before_core:
            raise ValueError('Source identity changed during SwiftPM execution')
    run_guarded(lambda: swift(*arguments, '--build-system', 'native', *options, '-j',
                              os.environ.get('DUST3D_BUILD_JOBS', '8'), '-Xswiftc', '-warnings-as-errors',
                              '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__dust3d_build',
                              '-Xlinker', str(metadata)), validate_after_build)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--core', type=Path, required=True)
    parser.add_argument('--build-root', type=Path, required=True)
    parser.add_argument('swift_arguments', nargs=argparse.REMAINDER)
    args = parser.parse_args()
    try:
        if not args.swift_arguments:
            raise ValueError('Provide a SwiftPM command, for example build')
        run(args.app, args.core, args.build_root, args.swift_arguments)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f'Local core integration failed: {error}', file=sys.stderr)
        return error.returncode if isinstance(error, subprocess.CalledProcessError) and error.returncode > 0 else 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
