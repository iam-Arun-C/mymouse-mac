#!/bin/zsh
set -e

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
DIST_DIR="$PROJECT_DIR/dist"
APP_NAME="MyMouse"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DMG_PATH="$DIST_DIR/MyMouse-Installer.dmg"

rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "==> 1. Generating AppIcon.icns..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
MODULE_CACHE="/tmp/mymouse_module_cache"
mkdir -p "$MODULE_CACHE"

swift -disable-sandbox -module-cache-path "$MODULE_CACHE" "$PROJECT_DIR/scripts/generate_icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$BUILD_DIR/AppIcon.icns"

echo "==> 2. Compiling Universal macOS Binary (arm64 + x86_64, macOS 12.0+ through 27.0.1+)..."
SOURCES=(
    "$PROJECT_DIR/Sources/Models.swift"
    "$PROJECT_DIR/Sources/KeyCodeHelper.swift"
    "$PROJECT_DIR/Sources/LiquidGlassComponents.swift"
    "$PROJECT_DIR/Sources/ClipboardManager.swift"
    "$PROJECT_DIR/Sources/MouseEngine.swift"
    "$PROJECT_DIR/Sources/InteractiveMouseView.swift"
    "$PROJECT_DIR/Sources/ShortcutRecorderSheet.swift"
    "$PROJECT_DIR/Sources/AppPickerSheet.swift"
    "$PROJECT_DIR/Sources/ContentView.swift"
    "$PROJECT_DIR/Sources/MyMouseApp.swift"
)

xcrun swiftc -O -swift-version 5 \
    -disable-sandbox \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macosx12.0 \
    -framework SwiftUI -framework AppKit -framework Carbon -framework ApplicationServices -framework ImageIO \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}_arm64"

xcrun swiftc -O -swift-version 5 \
    -disable-sandbox \
    -module-cache-path "$MODULE_CACHE" \
    -target x86_64-apple-macosx12.0 \
    -framework SwiftUI -framework AppKit -framework Carbon -framework ApplicationServices -framework ImageIO \
    "${SOURCES[@]}" \
    -o "$BUILD_DIR/${APP_NAME}_x86_64"

lipo -create -output "$BUILD_DIR/$APP_NAME" \
    "$BUILD_DIR/${APP_NAME}_arm64" \
    "$BUILD_DIR/${APP_NAME}_x86_64"

echo "==> 3. Creating $APP_NAME.app bundle..."
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$BUILD_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> 4. Signing $APP_NAME.app..."
codesign --force --deep --sign - "$APP_BUNDLE"

echo "==> 5. Staging DMG contents and creating ZIP archive..."
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$DIST_DIR/MyMouse.zip"

echo "==> Universal Binary & App Bundle ready!"
file "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
ls -lh "$DIST_DIR"
