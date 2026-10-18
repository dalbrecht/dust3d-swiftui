#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="${1:?usage: package_file_preview_extensions.sh editor.app binary-directory}"
BINARY_DIR="${2:?usage: package_file_preview_extensions.sh editor.app binary-directory}"
python3 - "$APP_BUNDLE/Contents/Info.plist" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as source:
    assert plistlib.load(source)['CFBundleIdentifier'] == 'org.dust3d.editor', 'Only the editor owns file preview providers'
PY
cd "$ROOT_DIR"
# The entry point builds every product before its final running-app check; packaging never compiles.
for EXTENSION_NAME in Dust3DQuickLookExtension Dust3DThumbnailExtension; do
    test -f "$BINARY_DIR/$EXTENSION_NAME" || { echo "Missing prebuilt provider: $EXTENSION_NAME" >&2; exit 1; }
done
test -d "$BINARY_DIR/Dust3DNative_Dust3DRendering.bundle" || { echo "Missing prebuilt shader resources" >&2; exit 1; }
for EXTENSION_NAME in Dust3DQuickLookExtension Dust3DThumbnailExtension; do
    python3 -B "$ROOT_DIR/script/check_running_app.py" "$APP_BUNDLE/Contents/MacOS/Dust3DEditor"
    EXTENSION_BUNDLE="$APP_BUNDLE/Contents/PlugIns/$EXTENSION_NAME.appex"
    mkdir -p "$EXTENSION_BUNDLE/Contents/MacOS" "$EXTENSION_BUNDLE/Contents/Resources"
    cp "$BINARY_DIR/$EXTENSION_NAME" "$EXTENSION_BUNDLE/Contents/MacOS/$EXTENSION_NAME"
    cp -R "$BINARY_DIR/Dust3DNative_Dust3DRendering.bundle" "$EXTENSION_BUNDLE/Contents/Resources/"
    python3 - "$EXTENSION_BUNDLE/Contents/Info.plist" "$EXTENSION_NAME" <<'PY'
import plistlib
import sys
name = sys.argv[2]
is_thumbnail = name == 'Dust3DThumbnailExtension'
suffix = 'thumbnail' if is_thumbnail else 'quicklook'
attributes = {'QLSupportedContentTypes': ['org.dust3d.document']}
if is_thumbnail:
    attributes['QLThumbnailMinimumDimension'] = 32
else:
    attributes.update(QLIsDataBasedPreview=False, QLSupportsSearchableItems=False)
metadata = {
    'CFBundleIdentifier': 'org.dust3d.editor.' + suffix,
    'CFBundleExecutable': name,
    'CFBundleName': name,
    'CFBundleDisplayName': 'Dust3D Thumbnails' if is_thumbnail else 'Dust3D Quick Look',
    'CFBundleInfoDictionaryVersion': '6.0',
    'CFBundleVersion': '1', 'CFBundleShortVersionString': '1.0',
    'CFBundlePackageType': 'XPC!', 'LSMinimumSystemVersion': '14.0',
    'NSExtension': {
        'NSExtensionPrincipalClass': name + ('.ThumbnailProvider' if is_thumbnail else '.PreviewViewController'),
        'NSExtensionPointIdentifier': 'com.apple.quicklook.' + ('thumbnail' if is_thumbnail else 'preview'),
        'NSExtensionAttributes': attributes,
    },
}
with open(sys.argv[1], 'wb') as target:
    plistlib.dump(metadata, target)
PY
    xattr -cr "$EXTENSION_BUNDLE"
    codesign --force --sign - --entitlements "$ROOT_DIR/assets/macos-file-previews/FilePreview.entitlements" "$EXTENSION_BUNDLE"
    codesign --verify --strict "$EXTENSION_BUNDLE"
done
