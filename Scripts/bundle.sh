#!/bin/bash
# Собирает LiquidIsland.app из SwiftPM-продукта.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/LiquidIsland.app"

cd "$ROOT"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/LiquidIsland"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/LiquidIsland"

# Иконка собирается из исходника Icon Composer: actool превращает .icon
# в .icns и Assets.car, которые и кладутся в бандл.
if [ -d "$ROOT/Resources/AppIcon.icon" ]; then
    xcrun actool "$ROOT/Resources/AppIcon.icon" \
        --compile "$APP/Contents/Resources" \
        --platform macosx \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$ROOT/build/icon.plist" >/dev/null 2>&1
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>LiquidIsland</string>
    <key>CFBundleDisplayName</key>
    <string>LiquidIsland</string>
    <key>CFBundleIdentifier</key>
    <string>app.liquidisland.LiquidIsland</string>
    <key>CFBundleExecutable</key>
    <string>LiquidIsland</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <!-- Без иконки в Dock: весь интерфейс — это остров. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>LiquidIsland читает название текущего трека из Музыки и Spotify.</string>
    <key>NSAudioCaptureUsageDescription</key>
    <string>LiquidIsland слушает системный выход, чтобы эквалайзер двигался в такт музыке.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "$APP"
