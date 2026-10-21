#!/usr/bin/env bash
# Builds Lumen in release mode, assembles build/Lumen.app and ad-hoc signs it.
# Usage: scripts/build-app.sh [--install]   (--install copies to ~/Applications)
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

APP="build/Lumen.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Lumen" "$APP/Contents/MacOS/Lumen"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>local.lumen.Lumen</string>
    <key>CFBundleName</key>
    <string>Lumen</string>
    <key>CFBundleDisplayName</key>
    <string>Lumen</string>
    <key>CFBundleExecutable</key>
    <string>Lumen</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    mkdir -p "$HOME/Applications"
    rm -rf "$HOME/Applications/Lumen.app"
    ditto "$APP" "$HOME/Applications/Lumen.app"
    echo "Installed to $HOME/Applications/Lumen.app"
fi
