#!/bin/zsh
# Buduje Phase0Spike i pakuje w .app poza iCloudem (~/Library/Caches), z ad-hoc podpisem.
set -e
cd "$(dirname "$0")"
BUILD=~/Library/Caches/MidniteDockBuild
swift build --scratch-path $BUILD
APP=$BUILD/MidniteDockPhase0.app
rm -rf $APP && mkdir -p $APP/Contents/MacOS
cp $BUILD/debug/Phase0Spike $APP/Contents/MacOS/
cat > $APP/Contents/Info.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.midnitemedia.midnitedock.phase0</string>
<key>CFBundleName</key><string>MidniteDock Phase0</string>
<key>CFBundleExecutable</key><string>Phase0Spike</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
codesign --force --sign - $APP
echo "APP: $APP"
