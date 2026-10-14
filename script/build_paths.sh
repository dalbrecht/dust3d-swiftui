#!/usr/bin/env bash
# Keep compiler caches outside cloud/File Provider checkouts: object files and
# module caches must remain materialized while native tools consume them.
DUST3D_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DUST3D_PROJECT_KEY="$(printf '%s' "$DUST3D_PROJECT_ROOT" | shasum -a 256 | cut -c 1-12)"
export DUST3D_BUILD_ROOT="${DUST3D_BUILD_ROOT:-${TMPDIR:-/tmp}/dust3d-native-$DUST3D_PROJECT_KEY}"
DUST3D_BINARY_DIR="$DUST3D_BUILD_ROOT/build/$(uname -m)-apple-macosx/debug"
