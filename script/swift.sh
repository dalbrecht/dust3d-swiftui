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
BUILD_IDENTITY_LINK_FLAGS=()
if BUILD_IDENTITY_FILE="$(python3 -B "$ROOT_DIR/script/build_identity.py" --root "$ROOT_DIR" --output "$DUST3D_BUILD_ROOT/identities")"; then
    BUILD_IDENTITY_LINK_FLAGS=(-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __dust3d_build -Xlinker "$BUILD_IDENTITY_FILE")
else
    echo "Continuing without embedded build identity; diagnostics will report it unavailable." >&2
fi
# Xcode 27's default SwiftPM build system failed signing its generated resource
# test bundle on this host. The native builder keeps the local package reproducible.
exec xcrun swift "$@" --build-system native --disable-sandbox \
    --scratch-path "$DUST3D_BUILD_ROOT/build" --cache-path "$DUST3D_BUILD_ROOT/swiftpm" \
    --config-path "$DUST3D_BUILD_ROOT/config" --security-path "$DUST3D_BUILD_ROOT/security" \
    -j "${DUST3D_BUILD_JOBS:-8}" -Xswiftc -warnings-as-errors "${BUILD_IDENTITY_LINK_FLAGS[@]}"
