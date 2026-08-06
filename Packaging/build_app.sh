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

echo "==> Code signing (identité locale stable, préserve les permissions Accessibilité entre rebuilds)"
# Signature ad-hoc ("--sign -") change de hash à chaque build, ce qui fait perdre
# la permission Accessibilité côté TCC (confirmé le 06/08/2026 sur PostIt : jusqu'à
# 3 entrées TCC distinctes pour un même Bundle ID après plusieurs rebuilds ad-hoc).
# "TurzxDeck Local Dev" est une identité de signature locale auto-signée, créée une
# fois dans le trousseau, réutilisée pour toutes les apps perso de Vassili sur cette
# machine — même principe qu'un certificat Developer ID payant, gratuit.
codesign --force --deep --identifier "com.vassi974.clipboarddoubleclick" --sign "TurzxDeck Local Dev" "$APP"

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
