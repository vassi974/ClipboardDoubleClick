#!/bin/bash
# Build the .app bundle and .dmg for ClipboardDoubleClick.
# Run from the repo root: ./Packaging/build_app.sh
set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Packaging/ClipboardDoubleClick.app"
DMG="$ROOT/ClipboardDoubleClick.dmg"

echo "==> Building release binary"
cd "$ROOT"
swift build -c release

echo "==> Assembling .app bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/ClipboardDoubleClick" "$APP/Contents/MacOS/ClipboardDoubleClick"
cp -R "$ROOT/.build/release/ClipboardDoubleClick_ClipboardDoubleClick.bundle" "$APP/Contents/Resources/"
cp "$ROOT/Packaging/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Packaging/AppIcon.icns" ]; then
  cp "$ROOT/Packaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

echo "==> Ad-hoc code signing (no paid Apple Developer account required)"
codesign --force --deep --sign - "$APP"

echo "==> Building .dmg"
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "ClipboardDoubleClick" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
rm -rf "$STAGE"

echo "==> Done: $DMG"
echo "Note: the app is ad-hoc signed, not notarized. On first launch, macOS/Gatekeeper"
echo "may warn it's from an unidentified developer — right-click the app > Open, or"
echo "allow it in System Settings > Privacy & Security."
