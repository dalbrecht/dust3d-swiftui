#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/build_paths.sh"
mkdir -p "$DUST3D_BUILD_ROOT"/{clang,swiftpm,config,security}
export CLANG_MODULE_CACHE_PATH="$DUST3D_BUILD_ROOT/clang"
export GIT_OPTIONAL_LOCKS=0
# Resolution can update Package.resolved; provenance must describe the core actually selected for this build.
xcrun swift package --disable-sandbox \
    --scratch-path "$DUST3D_BUILD_ROOT/build" --cache-path "$DUST3D_BUILD_ROOT/swiftpm" \
    --config-path "$DUST3D_BUILD_ROOT/config" --security-path "$DUST3D_BUILD_ROOT/security" resolve
HAS_BUILD_IDENTITY=false
if BUILD_IDENTITY_FILE="$(python3 -B "$ROOT_DIR/script/build_identity.py" --root "$ROOT_DIR" --output "$DUST3D_BUILD_ROOT/identities")"; then
    HAS_BUILD_IDENTITY=true
else
    echo "Continuing without embedded build identity; diagnostics will report it unavailable." >&2
fi
# SwiftPM never runs the core CMake quarantine gate. Refuse the unfinished GLB
# material catalog API before compiling the resolved checkout.
python3 -B "$ROOT_DIR/script/glb_catalog_quarantine.py" --core "$DUST3D_BUILD_ROOT/build/checkouts/dust3d-core"
# Xcode 27's default SwiftPM build system failed signing its generated resource
# test bundle on this host. The native builder keeps the local package reproducible.
set -- "$@" --build-system native --disable-sandbox \
    --scratch-path "$DUST3D_BUILD_ROOT/build" --cache-path "$DUST3D_BUILD_ROOT/swiftpm" \
    --config-path "$DUST3D_BUILD_ROOT/config" --security-path "$DUST3D_BUILD_ROOT/security" \
    -j "${DUST3D_BUILD_JOBS:-8}" -Xswiftc -warnings-as-errors
if [ "$HAS_BUILD_IDENTITY" = true ]; then
    set -- "$@" -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __dust3d_build -Xlinker "$BUILD_IDENTITY_FILE"
fi
xcrun swift "$@"

if [ "$HAS_BUILD_IDENTITY" = true ]; then
    if ! VERIFIED_BUILD_IDENTITY_FILE="$(python3 -B "$ROOT_DIR/script/build_identity.py" --root "$ROOT_DIR" --output "$DUST3D_BUILD_ROOT/identities")"; then
        echo "Cannot verify build identity after SwiftPM execution; do not package these artifacts." >&2
        exit 1
    fi
    # Content-addressed paths include revision, dirty status, source digest and resolved core identity.
    if [ "$BUILD_IDENTITY_FILE" != "$VERIFIED_BUILD_IDENTITY_FILE" ]; then
        echo "Source identity changed during SwiftPM execution; rebuild before packaging these artifacts." >&2
        exit 1
    fi
fi
