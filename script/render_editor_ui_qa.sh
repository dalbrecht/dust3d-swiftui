#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ $# -gt 1 ]]; then
    echo "Usage: $0 [output-directory]" >&2
    exit 64
fi
source "$ROOT_DIR/script/build_paths.sh"
RENDER_OUTPUT_DIRECTORY="${1:-$DUST3D_BUILD_ROOT/ui-qa}"
mkdir -p -- "$RENDER_OUTPUT_DIRECTORY"
export DUST3D_UI_QA_OUTPUT_DIR="$(cd "$RENDER_OUTPUT_DIRECTORY" && pwd)"
"$ROOT_DIR/script/swift.sh" test --filter 'PartModifierRenderingTests|ComponentStitchingRenderingTests'
