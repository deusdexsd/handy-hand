#!/bin/zsh
# Buduje uniwersalną (Apple Silicon + Intel) wersję Łapki i pakuje ją w DMG do zainstalowania na innych Macach.
# Użycie: ./make-dmg.sh [katalog-docelowy]   (domyślnie ~/Downloads)
set -e
cd "$(dirname "$0")"
OUT="${1:-$HOME/Downloads}"
CONFIG=release UNIVERSAL=1 ./build-app.sh > /dev/null || { echo "BUDOWANIE NIEUDANE"; exit 1; }
APP=~/Library/Caches/MidniteDockBuild-App/MidniteDock.app
STAGE=$(mktemp -d)/Łapka
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Łapka.app"
ln -s /Applications "$STAGE/Applications"
DMG="$OUT/Łapka.dmg"
rm -f "$DMG"
hdiutil create -volname "Łapka" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" > /dev/null
echo "architektury: $(lipo -archs "$STAGE/Łapka.app/Contents/MacOS/MidniteDock")"
echo "gotowe: $DMG ($(du -h "$DMG" | cut -f1))"
