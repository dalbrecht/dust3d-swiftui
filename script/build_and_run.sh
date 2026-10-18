#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Dust3DViewer"
DISPLAY_NAME="Dust3D Viewer"
BUNDLE_ID="org.dust3d.viewer"
DOCUMENT_ROLE="Viewer"
IS_QA=false
if [ "${1:-}" = "--editor" ] || [ "${1:-}" = "--editor-qa" ]; then
    APP_NAME="Dust3DEditor"
    DISPLAY_NAME="Dust3D Editor"
    BUNDLE_ID="org.dust3d.editor"
    DOCUMENT_ROLE="Editor"
    if [ "$1" = "--editor-qa" ]; then
        IS_QA=true
        DISPLAY_NAME="Dust3D Editor QA"
        BUNDLE_ID="org.dust3d.editor.combine-qa"
    fi
    shift
fi
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/build_paths.sh"
APP_OUTPUT_DEFAULT="$DUST3D_BUILD_ROOT/app"
ARCHIVE_OUTPUT_DEFAULT="$ROOT_DIR/dist"
if [ "$IS_QA" = true ]; then
    APP_OUTPUT_DEFAULT="$DUST3D_BUILD_ROOT/app-qa"
    ARCHIVE_OUTPUT_DEFAULT="$ROOT_DIR/dist/qa"
fi
APP_BUNDLE="${DUST3D_APP_OUTPUT_DIR:-$APP_OUTPUT_DEFAULT}/$APP_NAME.app"
ARCHIVE_OUTPUT_DIR="${DUST3D_ARCHIVE_OUTPUT_DIR:-$ARCHIVE_OUTPUT_DEFAULT}"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_BINARY="$APP_CONTENTS/MacOS/$APP_NAME"
cd "$ROOT_DIR"

case "$MODE" in
    run|--debug|--logs|--telemetry|--verify|--build-only) ;;
    *) echo "usage: $0 [--editor|--editor-qa] [--debug|--logs|--telemetry|--verify|--build-only]" >&2; exit 2 ;;
esac

python3 -B "$ROOT_DIR/script/check_running_app.py" "$APP_BINARY"
./script/swift.sh build --product "$APP_NAME"
if [ "$APP_NAME" = "Dust3DEditor" ] && [ "$IS_QA" = false ]; then
    for EXTENSION_NAME in Dust3DQuickLookExtension Dust3DThumbnailExtension; do
        ./script/swift.sh build --product "$EXTENSION_NAME"
    done
fi
BUILD_DIR="$DUST3D_BINARY_DIR"
# The target may have launched during compilation; check again before touching its bundle.
python3 -B "$ROOT_DIR/script/check_running_app.py" "$APP_BINARY"
mkdir -p "$APP_CONTENTS/MacOS" "$APP_CONTENTS/Resources" "$ARCHIVE_OUTPUT_DIR"
cp "$BUILD_DIR/$APP_NAME" "$APP_BINARY"
cp "$ROOT_DIR/assets/app-icons/$APP_NAME.icns" "$APP_CONTENTS/Resources/$APP_NAME.icns"

cp -R "$BUILD_DIR/Dust3DNative_Dust3DRendering.bundle" "$APP_CONTENTS/Resources/"
chmod +x "$APP_BINARY"
CLIPBOARD_TYPE_DECLARATION=""
if [ "$APP_NAME" = "Dust3DEditor" ]; then
    CLIPBOARD_TYPE_DECLARATION='<key>UTExportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>org.dust3d.node-clipboard.v1</string>
<key>UTTypeDescription</key><string>Dust3D Node Clipboard</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
</dict></array>'
fi
cat > "$APP_CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$DISPLAY_NAME</string>
<key>CFBundleIconFile</key><string>$APP_NAME.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleDocumentTypes</key><array><dict>
<key>CFBundleTypeName</key><string>Dust3D Document</string>
<key>CFBundleTypeRole</key><string>$DOCUMENT_ROLE</string>
<key>LSHandlerRank</key><string>Alternate</string>
<key>LSItemContentTypes</key><array><string>org.dust3d.document</string></array>
</dict></array>
<key>UTImportedTypeDeclarations</key><array><dict>
<key>UTTypeIdentifier</key><string>org.dust3d.document</string>
<key>UTTypeDescription</key><string>Dust3D Document</string>
<key>UTTypeConformsTo</key><array><string>public.data</string></array>
<key>UTTypeTagSpecification</key><dict><key>public.filename-extension</key><array><string>ds3</string></array></dict>
</dict></array>
$CLIPBOARD_TYPE_DECLARATION
</dict></plist>
PLIST
# Strip copied Finder metadata before ad-hoc signing this local development bundle.
if [ "$IS_QA" = true ]; then
    rm -rf "$APP_CONTENTS/PlugIns/Dust3DQuickLookExtension.appex" "$APP_CONTENTS/PlugIns/Dust3DThumbnailExtension.appex"
elif [ "$APP_NAME" = "Dust3DEditor" ]; then
    "$ROOT_DIR/script/package_file_preview_extensions.sh" "$APP_BUNDLE" "$BUILD_DIR"
fi
xattr -cr "$APP_BUNDLE"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
if [ "$APP_NAME" = "Dust3DEditor" ] && [ "$IS_QA" = false ]; then
    "$ROOT_DIR/script/check_file_preview_bundles.sh" "$APP_BUNDLE"
fi
# Launch Services detects rebuilt bundle metadata through the application directory timestamp.
/usr/bin/touch "$APP_BUNDLE"
# A ZIP keeps File Provider Finder metadata outside the app's sealed resources.
ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE_OUTPUT_DIR/$APP_NAME.zip"

case "$MODE" in
    --build-only) echo "$APP_BUNDLE" ;;
    run) /usr/bin/open -n "$APP_BUNDLE" ;;
    --debug) lldb -- "$APP_BINARY" ;;
    --logs)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --telemetry)
        /usr/bin/open -n "$APP_BUNDLE"
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify)
        /usr/bin/open -n "$APP_BUNDLE"
        sleep 1
        python3 -B "$ROOT_DIR/script/check_running_app.py" --expect-running "$APP_BINARY"
        ;;
esac
