#!/usr/bin/env bash
# Keep compiler caches outside cloud/File Provider checkouts and share them
# across linked worktrees. One build may use the shared root at a time.
DUST3D_PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
if [ -z "${DUST3D_BUILD_ROOT:-}" ]; then
    DUST3D_CACHE_IDENTITY="$DUST3D_PROJECT_ROOT"
    if DUST3D_GIT_COMMON_DIR="$(git -C "$DUST3D_PROJECT_ROOT" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
        if DUST3D_CANONICAL_COMMON_DIR="$(cd "$DUST3D_GIT_COMMON_DIR" && pwd -P)"; then
            DUST3D_CACHE_IDENTITY="$DUST3D_CANONICAL_COMMON_DIR"
        fi
    fi
    DUST3D_PROJECT_KEY="$(printf '%s' "$DUST3D_CACHE_IDENTITY" | shasum -a 256 | cut -c 1-12)"
    DUST3D_BUILD_ROOT="${TMPDIR:-/tmp}/dust3d-native-$DUST3D_PROJECT_KEY"
fi
export DUST3D_BUILD_ROOT
export DUST3D_UI_QA_OUTPUT_DIR="${DUST3D_UI_QA_OUTPUT_DIR:-$DUST3D_BUILD_ROOT/ui-qa}"
DUST3D_BINARY_DIR="$DUST3D_BUILD_ROOT/build/$(uname -m)-apple-macosx/debug"
