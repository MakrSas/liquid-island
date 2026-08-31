#!/bin/bash
# Собирает Liquid Island.dmg для выкладывания в релизы.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$ROOT/build/LiquidIsland.app/Contents/Info.plist" 2>/dev/null || echo 0.1.0)}"

"$ROOT/Scripts/bundle.sh" release >/dev/null

STAGE="$ROOT/build/dmg"
DMG="$ROOT/build/LiquidIsland-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$ROOT/build/LiquidIsland.app" "$STAGE/"
# Ярлык на «Программы» — привычный способ установки перетаскиванием.
ln -s /Applications "$STAGE/Applications"

# diskutil пришёл на смену hdiutil create, который теперь ругается устаревшим.
diskutil image create from "$STAGE" \
    --volumeName "Liquid Island" \
    --format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"
echo "$DMG"
