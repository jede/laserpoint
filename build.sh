#!/bin/bash
# Builds Laserpoint and assembles a runnable .app bundle.
#
#   ./build.sh        # release build (native arch) -> ./Laserpoint.app
#   ./build.sh run    # build, then launch the app
#   ./build.sh dmg    # universal build + ./Laserpoint-<VERSION>.dmg (for releases)
#
# Override the version with the VERSION env var, e.g. `VERSION=1.2.0 ./build.sh dmg`.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG=release
APP_NAME="Laserpoint"
APP_DIR="$APP_NAME.app"
BUNDLE_ID="com.laserpoint.launcher"
VERSION="${VERSION:-0.1.0}"

CMD="${1:-build}"

# Release DMGs are built universal (Apple Silicon + Intel); local builds use the
# host arch for speed.
ARCH_FLAGS=""
if [[ "$CMD" == "dmg" ]]; then
    ARCH_FLAGS="--arch arm64 --arch x86_64"
fi

echo "==> swift build -c $CONFIG $ARCH_FLAGS"
swift build -c "$CONFIG" $ARCH_FLAGS

BIN_PATH="$(swift build -c "$CONFIG" $ARCH_FLAGS --show-bin-path)/$APP_NAME"

echo "==> Assembling $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Compile the Icon Composer package into the bundle. actool emits Assets.car
# (the Liquid Glass icon used on macOS 26+) plus laserpoint.icns (the rasterized
# fallback for macOS 14/15). Both go in Resources; Info.plist references them
# below via CFBundleIconName / CFBundleIconFile.
ICON_NAME="laserpoint"   # basename of the .icon package and emitted .icns
ICON_SRC="Assets/$ICON_NAME.icon"
if [[ -d "$ICON_SRC" ]]; then
    echo "==> Compiling app icon"
    xcrun actool "$ICON_SRC" \
        --compile "$APP_DIR/Contents/Resources" \
        --app-icon "$ICON_NAME" \
        --platform macosx \
        --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$(mktemp)" >/dev/null
else
    echo "==> No icon at $ICON_SRC, skipping"
fi

# Menu-bar glyph (loaded at runtime as a template image).
if [[ -f "Assets/menubar.svg" ]]; then
    cp "Assets/menubar.svg" "$APP_DIR/Contents/Resources/menubar.svg"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>$ICON_NAME</string>
    <key>CFBundleIconName</key>
    <string>$ICON_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

# Ad-hoc code signature so macOS will run it and let it register a global hotkey.
echo "==> Codesigning (ad-hoc)"
codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "==> Built $APP_DIR"

case "$CMD" in
    run)
        echo "==> Launching"
        pkill -x "$APP_NAME" 2>/dev/null || true   # kill any prior instance
        open "$APP_DIR"
        ;;
    dmg)
        DMG="$APP_NAME-$VERSION.dmg"
        echo "==> Creating $DMG"
        STAGING="$(mktemp -d)"
        cp -R "$APP_DIR" "$STAGING/"
        ln -s /Applications "$STAGING/Applications"   # drag-to-install target
        rm -f "$DMG"
        hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" \
            -ov -format UDZO "$DMG" >/dev/null
        rm -rf "$STAGING"
        echo "==> Built $DMG"
        ;;
esac
