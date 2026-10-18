#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/build_paths.sh"
if rg -n '#include\s*[<"]Q[A-Z]|\b(QObject|QString|QImage|QWidget)\b' Sources "$DUST3D_BUILD_ROOT/build/checkouts/dust3d-core/dust3d" "$DUST3D_BUILD_ROOT/build/checkouts/dust3d-core/native/Engine"; then
    echo "Qt references found in native targets" >&2
    exit 1
fi
for APP_NAME in Dust3DViewer Dust3DEditor Dust3DQuickLookExtension Dust3DThumbnailExtension; do
    APP_BINARY="$DUST3D_BINARY_DIR/$APP_NAME"
    if /usr/bin/otool -L "$APP_BINARY" | rg -i 'Qt(Core|Gui|Widgets|OpenGL|Svg|Multimedia)|/Qt[^/]*\.framework'; then
        echo "Qt linked into $APP_NAME" >&2
        exit 1
    fi
done
echo "Native sources and app and extension linkages are Qt-free."
