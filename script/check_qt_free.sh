#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/script/build_paths.sh"

check_no_qt() {
    local match_message="$1"
    local failure_message="$2"
    local scan_status
    shift 2
    if /usr/bin/grep -E "$@"; then
        echo "$match_message" >&2
        return 1
    else
        scan_status=$?
    fi
    if [[ "$scan_status" -ne 1 ]]; then
        echo "$failure_message" >&2
        return "$scan_status"
    fi
}

core_sources="$DUST3D_BUILD_ROOT/build/checkouts/dust3d-core"
check_no_qt "Qt references found in native targets" "Could not scan native sources for Qt references" \
    -nrI '#include[[:space:]]*[<"]Q[A-Z]|(^|[^[:alnum:]_])(QObject|QString|QImage|QWidget)([^[:alnum:]_]|$)' \
    Sources "$core_sources/dust3d" "$core_sources/native/Engine"

mkdir -p "$DUST3D_BUILD_ROOT/clang"
manifest="$(CLANG_MODULE_CACHE_PATH="$DUST3D_BUILD_ROOT/clang" xcrun swift package \
    --scratch-path "$DUST3D_BUILD_ROOT/build" --cache-path "$DUST3D_BUILD_ROOT/swiftpm" \
    --config-path "$DUST3D_BUILD_ROOT/config" --security-path "$DUST3D_BUILD_ROOT/security" dump-package)"
products="$(python3 -c '
import json
import sys

products = json.load(sys.stdin)["products"]
print("\n".join(product["name"] for product in products if "executable" in product["type"]))
' <<< "$manifest")"
if [[ -z "$products" ]]; then
    echo "No native executable products found in Package.swift" >&2
    exit 1
fi

while IFS= read -r product; do
    binary="$DUST3D_BINARY_DIR/$product"
    if ! linkage="$(/usr/bin/otool -arch all -L "$binary")"; then
        echo "Could not inspect linkage for $product" >&2
        exit 1
    fi
    case "$linkage" in
        "$binary:"|"$binary:"$'\n'*|"$binary (architecture "*) ;;
        *)
            # otool can report invalid input on stdout with an exit status of zero.
            printf '%s\n' "$linkage" >&2
            echo "Could not inspect Mach-O linkage for $product" >&2
            exit 1
            ;;
    esac
    headers="$(/usr/bin/otool -arch all -h "$binary")"
    # Each architecture must be a Mach-O executable (MH_EXECUTE has file type 2).
    if ! awk '
        $1 ~ /^0x(feedface|feedfacf|cefaedfe|cffaedfe)$/ {
            found = 1
            if ($5 != 2) invalid = 1
        }
        END { exit (!found || invalid) }
    ' <<< "$headers"; then
        echo "Expected a Mach-O executable for $product" >&2
        exit 1
    fi
    check_no_qt "Qt linked into $product" "Could not scan linkage for $product" \
        -i '^[[:space:]]+(.*/)?((lib)?Qt[[:alnum:]_]+(\.[0-9]+)*\.dylib|Qt[^/]*\.framework/[^[:space:]]+|Qt[0-9]*(Core|Gui|Widgets|OpenGL|Svg|Multimedia))[[:space:]]' \
        <<< "$linkage"
done <<< "$products"

echo "Native sources and executable product linkages are Qt-free."
