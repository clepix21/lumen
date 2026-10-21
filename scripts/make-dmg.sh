#!/usr/bin/env bash
# Builds Lumen.app and packs it into build/Lumen-<version>.dmg, with a shortcut to Applications.
# Usage: LUMEN_VERSION=0.2.0 scripts/make-dmg.sh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${LUMEN_VERSION:-0.1.0}"
LUMEN_VERSION="$VERSION" bash scripts/build-app.sh

STAGING="build/dmg"
DMG="build/Lumen-${VERSION}.dmg"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto build/Lumen.app "$STAGING/Lumen.app"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Lumen" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
echo "Built $DMG"
