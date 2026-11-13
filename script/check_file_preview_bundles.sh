#!/usr/bin/env bash
set -euo pipefail
APP_BUNDLE="${1:?usage: check_file_preview_bundles.sh path/to/Dust3DEditor.app}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for owner in "$APP_BUNDLE" "$APP_BUNDLE/Contents/PlugIns/Dust3DQuickLookExtension.appex" "$APP_BUNDLE/Contents/PlugIns/Dust3DThumbnailExtension.appex"; do
    python3 -B "$ROOT_DIR/script/check_rig_resources.py" "$owner/Contents/Resources/Dust3DNative_Dust3DKit.bundle"
done
python3 - "$APP_BUNDLE" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

def build_identity(binary):
    section = subprocess.check_output(
        ['/usr/bin/otool', '-X', '-s', '__TEXT', '__dust3d_build', str(binary)], text=True)
    # Ignore load addresses, which differ between the host and provider executables.
    words = [word for line in section.splitlines() for word in line.split()[1:]]
    if not words:
        raise SystemExit(f'Missing embedded build identity: {binary}')
    return ''.join(words)


app = pathlib.Path(sys.argv[1])
editor_identity = build_identity(app / 'Contents' / 'MacOS' / 'Dust3DEditor')
for name, suffix, point, principal in [
    ('Dust3DQuickLookExtension', 'quicklook', 'com.apple.quicklook.preview', 'PreviewViewController'),
    ('Dust3DThumbnailExtension', 'thumbnail', 'com.apple.quicklook.thumbnail', 'ThumbnailProvider'),
]:
    bundle = app / 'Contents' / 'PlugIns' / (name + '.appex')
    assert bundle.is_dir(), f'Missing file preview extension: {bundle}'
    metadata = plistlib.loads((bundle / 'Contents' / 'Info.plist').read_bytes())
    assert metadata['CFBundleIdentifier'] == 'org.dust3d.editor.' + suffix
    assert metadata['CFBundleExecutable'] == name
    extension = metadata['NSExtension']
    assert extension['NSExtensionPointIdentifier'] == point
    assert extension['NSExtensionPrincipalClass'] == name + '.' + principal
    assert extension['NSExtensionAttributes']['QLSupportedContentTypes'] == ['org.dust3d.document']
    shader = bundle / 'Contents' / 'Resources' / 'Dust3DNative_Dust3DRendering.bundle' / 'Shaders.metal'
    assert shader.is_file(), f'Missing packaged preview shaders: {shader}'
    binary = bundle / 'Contents' / 'MacOS' / name
    if build_identity(binary) != editor_identity:
        raise SystemExit(f'{name}: embedded build identity differs from Dust3DEditor')
    symbols = subprocess.check_output(['xcrun', 'nm', '-u', str(binary)], text=True)
    assert '_NSExtensionMain' in symbols, 'Extension does not use the SDK entry point'
    links = subprocess.check_output(['/usr/bin/otool', '-L', str(binary)], text=True)
    assert not any(token in links for token in ('QtCore', 'QtGui', 'QtWidgets', '/Qt.'))
    subprocess.run(['codesign', '--verify', '--strict', str(bundle)], check=True)
    signed = subprocess.run(['codesign', '--display', '--entitlements', ':-', str(bundle)],
                            check=True, capture_output=True)
    entitlements = plistlib.loads(signed.stdout)
    assert entitlements.get('com.apple.security.app-sandbox') is True
    assert entitlements.get('com.apple.security.files.user-selected.read-only') is True
    assert not entitlements.get('com.apple.security.network.client', False)
    print(f'{name}: metadata, build identity, shader resources, entry point, readonly sandbox and signature verified')
PY
