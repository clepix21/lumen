#!/usr/bin/env bash
# Regenerates assets/AppIcon.icns and assets/icon.png from scripts/draw-icon.swift.
# Each size is drawn directly (not downscaled) so small icons stay sharp.
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET" assets

for size in 16 32 128 256 512; do
    swift scripts/draw-icon.swift "$ICONSET/icon_${size}x${size}.png" "$size"
    swift scripts/draw-icon.swift "$ICONSET/icon_${size}x${size}@2x.png" "$((size * 2))"
done

iconutil -c icns "$ICONSET" -o assets/AppIcon.icns
cp "$ICONSET/icon_256x256@2x.png" assets/icon.png
echo "Wrote assets/AppIcon.icns and assets/icon.png"
