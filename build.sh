#!/bin/zsh
set -euo pipefail
SOURCE_DIR="${0:A:h}"
BUILD_DIR="$SOURCE_DIR/build"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="${KOL_CHEN_APP_PATH:-$BUILD_DIR/kol-chen.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD_DIR/module-cache"
xcrun swiftc -O -swift-version 6 -parse-as-library \
  -target arm64-apple-macos15.0 -sdk "$SDK" \
  -module-cache-path "$BUILD_DIR/module-cache" \
  "$SOURCE_DIR/Sources/"*.swift \
  -o "$APP/Contents/MacOS/kol-chen"
cp "$SOURCE_DIR/Info.plist" "$APP/Contents/Info.plist"
if [[ -f "$SOURCE_DIR/AppIcon.icns" ]]; then
  cp "$SOURCE_DIR/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
if [[ -d "$SOURCE_DIR/Resources" ]]; then
  cp -R "$SOURCE_DIR/Resources/." "$APP/Contents/Resources/"
fi
codesign --force --sign - --identifier com.seffyfisher.kol-chen "$APP"
echo "Built: $APP"
