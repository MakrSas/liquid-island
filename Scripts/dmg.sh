#!/bin/bash
# Собирает Liquid Island.dmg: окно с фоном, приложение слева, «Программы»
# справа. Раскладка задаётся здесь, поэтому фон надо рисовать под неё —
# размеры перечислены ниже и продублированы в README.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="LiquidIsland"
VOLUME="Liquid Island"

# --- Раскладка окна установщика, в точках ---
WINDOW_WIDTH=660
WINDOW_HEIGHT=420
ICON_SIZE=128
APP_X=180;  APP_Y=210      # приложение слева
LINK_X=480; LINK_Y=210     # ярлык «Программы» справа

# Границы окна Finder задаются координатами углов, а не размерами.
RIGHT=$(( 200 + WINDOW_WIDTH ))
BOTTOM=$(( 120 + WINDOW_HEIGHT ))

"$ROOT/Scripts/bundle.sh" release >/dev/null
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/build/$APP_NAME.app/Contents/Info.plist")"

STAGE="$ROOT/build/dmg"
RAW="$ROOT/build/raw.dmg"
DMG="$ROOT/build/$APP_NAME-$VERSION.dmg"
rm -rf "$STAGE" "$RAW" "$DMG"
mkdir -p "$STAGE/.background"

cp -R "$ROOT/build/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Фон необязателен: без него окно будет просто пустым, но раскладка сохранится.
BACKGROUND="$ROOT/Resources/dmg-background.png"
HAS_BACKGROUND=false
if [ -f "$BACKGROUND" ]; then
    # Картинка рисуется в двойном разрешении, а Finder ждёт точки. TIFF с
    # двумя представлениями решает это: на обычном экране берётся одно,
    # на Retina — другое.
    tiffutil -cathidpicheck "$BACKGROUND" -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 \
        || cp "$BACKGROUND" "$STAGE/.background/background.tiff"
    HAS_BACKGROUND=true
fi

# Записываемый образ: раскладку Finder может сохранить только в такой.
diskutil image create from "$STAGE" \
    --volumeName "$VOLUME" \
    --format UDRW \
    "$RAW" >/dev/null

MOUNT="$(diskutil image attach "$RAW" --mountOptions nobrowse | \
    grep -o '/Volumes/.*' | head -1)"

osascript <<APPLESCRIPT >/dev/null
tell application "Finder"
    tell disk "$VOLUME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, ${RIGHT}, ${BOTTOM}}
        set options to the icon view options of container window
        set arrangement of options to not arranged
        set icon size of options to $ICON_SIZE
        if $HAS_BACKGROUND then
            set background picture of options to file ".background:background.tiff"
        end if
        set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
        set position of item "Applications" of container window to {$LINK_X, $LINK_Y}
        close
        open
        update without registering applications
        delay 1
    end tell
end tell
APPLESCRIPT

MOUNT_SOURCE="$RAW"
diskutil eject "$MOUNT" >/dev/null
# Сжатый образ только для чтения: раскладка уже записана внутрь.
diskutil image create from "$RAW" --format UDZO "$DMG" >/dev/null

rm -rf "$STAGE" "$RAW"
echo "$DMG"
