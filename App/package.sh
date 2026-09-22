#!/bin/zsh
# Buduje i kopiuje MidniteDock.app do App/dist (gotowe do uruchomienia; ad-hoc podpis).
cd "$(dirname "$0")"
CONFIG=release ./build-app.sh > /dev/null || exit 1
rm -rf dist && mkdir -p dist
cp -R ~/Library/Caches/MidniteDockBuild-App/MidniteDock.app "dist/Handy.app"
echo "gotowe: $(pwd)/dist/Handy.app"
