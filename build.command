#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Duplicate Finder"
BUNDLE_ID="com.tayron.duplicatefinder"
BUILD_DIR="$PWD/.build/release"
APP_DIR="$PWD/dist/$APP_NAME.app"

xcode-select -p >/dev/null 2>&1 || { echo "Xcode Command Line Tools are required."; exit 1; }
swift build -c release
rm -rf "$APP_DIR" "$PWD/dist/$APP_NAME.dmg"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

# Build the macOS app icon from the included 1024px artwork.
ICONSET="$PWD/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
ICON_SRC="$PWD/Resources/AppIcon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$BUILD_DIR/DuplicateFinder" "$APP_DIR/Contents/MacOS/DuplicateFinder"
chmod +x "$APP_DIR/Contents/MacOS/DuplicateFinder"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>DuplicateFinder</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>Duplicate Finder</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

mkdir -p dist
hdiutil create -volname "Duplicate Finder" -srcfolder "dist/$APP_NAME.app" -ov -format UDZO "dist/$APP_NAME.dmg" >/dev/null

echo
echo "Created: $APP_DIR"
echo "Created: $PWD/dist/$APP_NAME.dmg"
