#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/build_paths.sh"
mkdir -p "$DUST3D_BUILD_ROOT"/{clang,swiftpm,config,security}
export CLANG_MODULE_CACHE_PATH="$DUST3D_BUILD_ROOT/clang"
export GIT_OPTIONAL_LOCKS=0
# Xcode 27's default SwiftPM build system failed signing its generated resource
# test bundle on this host. The native builder keeps the local package reproducible.
exec xcrun swift "$@" --build-system native --disable-sandbox \
    --scratch-path "$DUST3D_BUILD_ROOT/build" --cache-path "$DUST3D_BUILD_ROOT/swiftpm" \
    --config-path "$DUST3D_BUILD_ROOT/config" --security-path "$DUST3D_BUILD_ROOT/security" \
    -j "${DUST3D_BUILD_JOBS:-8}" -Xswiftc -warnings-as-errors
