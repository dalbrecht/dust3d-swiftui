#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep this integration check separate from running QA apps and their documents.
APP_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dust3d-bundle-rebuild.XXXXXX")"
trap 'rm -rf "$APP_TEST_DIR"' EXIT
cd "$ROOT_DIR"
verify_archive() {
    python3 -B - "$1" "$2" <<'PYARCHIVE'
from pathlib import Path
import hashlib
import os
import stat
import subprocess
import sys
import tempfile
import zipfile
bundle, archive = map(Path, sys.argv[1:])
def digest(stream):
    value = hashlib.sha256()
    while chunk := stream.read(1024 * 1024):
        value.update(chunk)
    return value.hexdigest()
def tree(root):
    result = {}
    def visit(path, name):
        mode = path.lstat().st_mode
        kind = stat.S_IFMT(mode)
        if stat.S_ISDIR(mode):
            result[name + '/'] = (kind, stat.S_IMODE(mode), None)
            for child in sorted(path.iterdir()):
                visit(child, name + '/' + child.name)
        elif stat.S_ISLNK(mode):
            result[name] = (kind, stat.S_IMODE(mode), os.fsencode(os.readlink(path)))
        elif stat.S_ISREG(mode):
            with path.open('rb') as source:
                result[name] = (kind, stat.S_IMODE(mode), digest(source))
        else:
            raise AssertionError(f'Unexpected bundle entry: {path}')
    visit(root, root.name)
    return result
expected = tree(bundle)
with zipfile.ZipFile(archive) as source:
    actual = {}
    for entry in source.infolist():
        mode = entry.external_attr >> 16
        kind = stat.S_IFMT(mode)
        assert entry.filename not in actual, 'Archive must not contain duplicate entries'
        if stat.S_ISDIR(mode):
            payload = None
        elif stat.S_ISLNK(mode):
            payload = source.read(entry)
        else:
            assert stat.S_ISREG(mode), f'Unexpected archive entry: {entry.filename}'
            with source.open(entry) as stream:
                payload = digest(stream)
        actual[entry.filename] = (kind, stat.S_IMODE(mode), payload)
    assert actual == expected, 'ZIP must contain exactly the signed tree, types, modes and bytes'
with tempfile.TemporaryDirectory(prefix='dust3d-archive-extract-') as temporary:
    subprocess.run(['ditto', '-x', '-k', str(archive), temporary], check=True)
    extracted = Path(temporary) / bundle.name
    assert tree(extracted) == expected, 'Extracted tree must preserve bytes, modes and symbolic links'
    subprocess.run(['codesign', '--verify', '--deep', '--strict', str(extracted)], check=True)
print(f'{bundle.name}: exact archive and extracted signature verified')
PYARCHIVE
}
archive_manifest() {
    python3 - "$ROOT_DIR/dist" <<'PYTHON'
from pathlib import Path
import hashlib
import json
import sys
root = Path(sys.argv[1])
manifest = {}
for name in ('Dust3DEditor', 'Dust3DViewer'):
    archive = root / (name + '.zip')
    manifest[name] = None if not archive.exists() else [
        archive.stat().st_mtime_ns, hashlib.sha256(archive.read_bytes()).hexdigest()
    ]
print(json.dumps(manifest, sort_keys=True))
PYTHON
}
archive_manifest > "$APP_TEST_DIR/default-archives-before.json"
export DUST3D_ARCHIVE_OUTPUT_DIR="$APP_TEST_DIR/archives"
for app in Dust3DEditor Dust3DViewer; do
    app_arguments=(--build-only)
    if [ "$app" = "Dust3DEditor" ]; then app_arguments=(--editor --build-only); fi
    DUST3D_APP_OUTPUT_DIR="$APP_TEST_DIR" ./script/build_and_run.sh "${app_arguments[@]}"
    bundle="$APP_TEST_DIR/$app.app"
    touch -t 200001010000 "$bundle"
    DUST3D_APP_OUTPUT_DIR="$APP_TEST_DIR" ./script/build_and_run.sh "${app_arguments[@]}"
    python3 - "$bundle" <<'PY'
from pathlib import Path
import plistlib
import sys
bundle = Path(sys.argv[1])
plist = bundle / 'Contents/Info.plist'
with plist.open('rb') as source:
    metadata = plistlib.load(source)
icon = bundle / 'Contents/Resources' / metadata['CFBundleIconFile']
assert icon.read_bytes()[:4] == b'icns', 'Declared app icon must be present'
assert bundle.stat().st_mtime_ns >= max(plist.stat().st_mtime_ns, icon.stat().st_mtime_ns), \
    'Rebuild must refresh the app root modification time after its metadata/resources'
print(f'{bundle.name}: rebuilt directory timestamp includes current plist and icon')
PY
    python3 -B "$ROOT_DIR/script/check_rig_resources.py" "$bundle/Contents/Resources/Dust3DNative_Dust3DKit.bundle"
    codesign --verify --deep --strict "$bundle"
    verify_archive "$bundle" "$DUST3D_ARCHIVE_OUTPUT_DIR/$app.zip"
done
python3 -B "$ROOT_DIR/script/check_about_resources.py" "$ROOT_DIR" "$DUST3D_ARCHIVE_OUTPUT_DIR" "$APP_TEST_DIR/about-resources.json"
# Reusing the QA identity must remove copied provider bundles rather than registering duplicates.
qa_output="$APP_TEST_DIR/qa"
mkdir -p "$qa_output/Dust3DEditor.app/Contents/PlugIns/Dust3DQuickLookExtension.appex"
mkdir -p "$qa_output/Dust3DEditor.app/Contents/PlugIns/Dust3DThumbnailExtension.appex"
DUST3D_APP_OUTPUT_DIR="$qa_output" DUST3D_ARCHIVE_OUTPUT_DIR="$APP_TEST_DIR/qa-archives" \
    ./script/build_and_run.sh --editor-qa --build-only
python3 - "$qa_output/Dust3DEditor.app" <<'PYQA'
from pathlib import Path
import plistlib
import sys
bundle = Path(sys.argv[1])
with (bundle / 'Contents/Info.plist').open('rb') as source:
    metadata = plistlib.load(source)
assert metadata['CFBundleIdentifier'] == 'org.dust3d.editor.combine-qa'
assert metadata['CFBundleName'] == 'Dust3D Editor QA'
assert not list((bundle / 'Contents/PlugIns').glob('*.appex')), 'QA apps must not own preview providers'
print('QA bundle reuses the existing identity and has no preview providers')
PYQA
python3 -B "$ROOT_DIR/script/check_rig_resources.py" "$qa_output/Dust3DEditor.app/Contents/Resources/Dust3DNative_Dust3DKit.bundle"
codesign --verify --deep --strict "$qa_output/Dust3DEditor.app"
verify_archive "$qa_output/Dust3DEditor.app" "$APP_TEST_DIR/qa-archives/Dust3DEditor.zip"
archive_manifest > "$APP_TEST_DIR/default-archives-after.json"
cmp "$APP_TEST_DIR/default-archives-before.json" "$APP_TEST_DIR/default-archives-after.json"
for app in Dust3DEditor Dust3DViewer; do
    test -s "$DUST3D_ARCHIVE_OUTPUT_DIR/$app.zip"
done
# Exercise the packaged entry point, including its native encoder wiring.
editor="$APP_TEST_DIR/Dust3DEditor.app/Contents/MacOS/Dust3DEditor"
source_archive="$ROOT_DIR/Tests/Dust3DKitTests/Fixtures/Capsule.ds3"
"$editor" "$source_archive" -o "$APP_TEST_DIR/copy.ds3" -o "$APP_TEST_DIR/capsule.obj" -o "$APP_TEST_DIR/capsule.fbx"
cmp "$source_archive" "$APP_TEST_DIR/copy.ds3"
awk '/^v /{vertices++} /^f /{faces++} END{exit !(vertices==42 && faces==48)}' "$APP_TEST_DIR/capsule.obj"
test "$(head -c 18 "$APP_TEST_DIR/capsule.fbx")" = 'Kaydara FBX Binary'
echo "Rebuild regression leaves default archives unchanged and packages only isolated archives."
