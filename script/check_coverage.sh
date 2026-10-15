#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/script/build_paths.sh"
cd "$ROOT_DIR"
BINARY="$DUST3D_BINARY_DIR/Dust3DNativePackageTests.xctest/Contents/MacOS/Dust3DNativePackageTests"
PROFILE="$DUST3D_BUILD_ROOT/build/debug/codecov/default.profdata"
xcrun llvm-cov export "$BINARY" -instr-profile="$PROFILE" -summary-only \
    Sources/Dust3DKit/*.swift Sources/Dust3DDocument/*.swift \
    | python3 "$ROOT_DIR/script/check_coverage.py"
