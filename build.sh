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
#
# We build each arch separately with the native build system and lipo them
# together, rather than `swift build --arch arm64 --arch x86_64`. The multi-arch
# flag routes through Xcode's build system, which breaks on some Xcode versions
# (duplicate-output-file / unsupported-Swift-version errors) — the per-triple
# build avoids that and works regardless of the toolchain on the runner.
if [[ "$CMD" == "dmg" ]]; then
    echo "==> swift build -c $CONFIG (universal: arm64 + x86_64)"
    swift build -c "$CONFIG" --triple arm64-apple-macosx
    swift build -c "$CONFIG" --triple x86_64-apple-macosx
    ARM_BIN="$(swift build -c "$CONFIG" --triple arm64-apple-macosx --show-bin-path)/$APP_NAME"
    X86_BIN="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx --show-bin-path)/$APP_NAME"
    BIN_PATH="$(mktemp -d)/$APP_NAME"
    lipo -create -output "$BIN_PATH" "$ARM_BIN" "$X86_BIN"
else
    echo "==> swift build -c $CONFIG"
    swift build -c "$CONFIG"
    BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
fi

echo "==> Assembling $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Compile the Icon Composer package into a traditional .icns referenced by
# CFBundleIconFile (below). We deliberately use the .icns rather than the
# Assets.car / CFBundleIconName path: on macOS 26 Finder prefers the Assets.car
# icon but can't render it from a read-only volume (a mounted DMG), and won't
# fall back to the .icns — so the icon would be missing in the DMG. The .icns is
# read directly on any volume. (--minimum-deployment-target is required: without
# it actool fails to resolve the glyph layer and emits a background-only icon.)
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
    # Assets.car holds the Liquid Glass icon, which we don't reference (see above)
    # — drop it so it doesn't bloat the bundle or get preferred by Finder.
    rm -f "$APP_DIR/Contents/Resources/Assets.car"
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
