#!/bin/zsh
# Buduje MidniteDock i pakuje w .app poza iCloudem (~/Library/Caches), z ad-hoc podpisem.
set -e
cd "$(dirname "$0")"
BUILD=~/Library/Caches/MidniteDockBuild-App
CONFIG=${CONFIG:-debug}
if ! swift build -c $CONFIG --scratch-path $BUILD > /tmp/dock-build.log 2>&1; then grep -E "error" /tmp/dock-build.log | head -20; echo "BUDOWANIE NIEUDANE (nie pakuję starej wersji)"; exit 1; fi
CAP="$(echo ${CONFIG:0:1} | tr a-z A-Z)${CONFIG:1}"
BIN=$(find $BUILD -path "*Products/$CAP/MidniteDock" -type f 2>/dev/null | head -1)
[ -z "$BIN" ] && BIN=$(find $BUILD -name MidniteDock -type f -perm +111 | grep -v dSYM | head -1)
APP=$BUILD/MidniteDock.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp "$BIN" $APP/Contents/MacOS/MidniteDock
mkdir -p $APP/Contents/Resources && cp Resources/AppIcon.icns $APP/Contents/Resources/AppIcon.icns
mkdir -p $APP/Contents/Resources/creatures && cp Resources/creatures/*.svg $APP/Contents/Resources/creatures/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.midnitemedia.midnitedock</string>
<key>CFBundleName</key><string>Łapka</string>
<key>CFBundleDisplayName</key><string>Łapka</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleExecutable</key><string>MidniteDock</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>$(date +%Y-%m-%d.%H:%M)</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
xattr -cr $APP
codesign --force --sign - $APP
echo "APP: $APP"
