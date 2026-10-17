#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICON_TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_TEST_DIR"' EXIT
for app in Dust3DEditor Dust3DViewer; do
    iconutil --convert iconset --output "$ICON_TEST_DIR/$app.iconset" "$ROOT_DIR/assets/app-icons/$app.icns"
    for size in 16 32 128 256 512; do
        for scale in 1 2; do
            suffix=""
            if [ "$scale" -eq 2 ]; then suffix="@2x"; fi
            image="$ICON_TEST_DIR/$app.iconset/icon_${size}x${size}${suffix}.png"
            expected=$((size * scale))
            dimensions="$(sips -g pixelWidth -g pixelHeight "$image")"
            test "$(awk '/pixelWidth:/ {print $2}' <<< "$dimensions")" -eq "$expected"
            test "$(awk '/pixelHeight:/ {print $2}' <<< "$dimensions")" -eq "$expected"
        done
    done
done
echo "Editor and viewer icon resources decode at every required size."
