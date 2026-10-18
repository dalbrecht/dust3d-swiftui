#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep this integration check separate from running QA apps and their documents.
APP_TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/dust3d-bundle-rebuild.XXXXXX")"
trap 'rm -rf "$APP_TEST_DIR"' EXIT
cd "$ROOT_DIR"
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
    codesign --verify --deep --strict "$bundle"
done
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
codesign --verify --deep --strict "$qa_output/Dust3DEditor.app"
archive_manifest > "$APP_TEST_DIR/default-archives-after.json"
cmp "$APP_TEST_DIR/default-archives-before.json" "$APP_TEST_DIR/default-archives-after.json"
for app in Dust3DEditor Dust3DViewer; do
    test -s "$DUST3D_ARCHIVE_OUTPUT_DIR/$app.zip"
done
echo "Rebuild regression leaves default archives unchanged and packages only isolated archives."
