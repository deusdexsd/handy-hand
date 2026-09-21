#!/bin/zsh
# Uruchomienie deweloperskie: dane testowe i zapis w ~/Library/Caches/MidniteDockDev (nie ruszamy prawdziwych danych).
cd "$(dirname "$0")"
DEV=~/Library/Caches/MidniteDockDev
APP=~/Library/Caches/MidniteDockBuild-App/MidniteDock.app
./build-app.sh > /dev/null || exit 1
[ -d "$DEV/media/SFX" ] || $APP/Contents/MacOS/MidniteDock --make-devmedia "$DEV/media"
[ "$1" = "--fresh" ] && rm -rf "$DEV/data"
MIDNITEDOCK_DATA_DIR="$DEV/data" MIDNITEDOCK_DEV_MEDIA="$DEV/media" exec $APP/Contents/MacOS/MidniteDock
