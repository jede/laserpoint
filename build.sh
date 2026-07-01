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
    # Resource bundles (e.g. KeyboardShortcuts' localizations) are
    # architecture-independent, so take them from either per-triple bin path.
    RES_BIN="$(swift build -c "$CONFIG" --triple arm64-apple-macosx --show-bin-path)"
    ARM_BIN="$RES_BIN/$APP_NAME"
    X86_BIN="$(swift build -c "$CONFIG" --triple x86_64-apple-macosx --show-bin-path)/$APP_NAME"
    BIN_PATH="$(mktemp -d)/$APP_NAME"
    lipo -create -output "$BIN_PATH" "$ARM_BIN" "$X86_BIN"
else
    echo "==> swift build -c $CONFIG"
    swift build -c "$CONFIG"
    RES_BIN="$(swift build -c "$CONFIG" --show-bin-path)"
    BIN_PATH="$RES_BIN/$APP_NAME"
fi

echo "==> Assembling $APP_DIR (v$VERSION)"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy SwiftPM-generated resource bundles (e.g.
# KeyboardShortcuts_KeyboardShortcuts.bundle, which holds its localizations).
# Without these, `Bundle.module` traps at runtime — the KeyboardShortcuts
# recorder in Settings crashes the app on open.
shopt -s nullglob
for bundle in "$RES_BIN"/*.bundle; do
    echo "==> Bundling resources: $(basename "$bundle")"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
shopt -u nullglob

# Compile the Icon Composer package. actool (Xcode 26+) emits two artifacts we
# keep both of:
#   • Assets.car — the full Liquid Glass icon, referenced by CFBundleIconName.
#     This is what renders at high resolution with specular lighting/translucency
#     on macOS 26+ once the app is installed on a read-write volume.
#   • laserpoint.icns — a flat fallback (max 256px) referenced by CFBundleIconFile
#     for older macOS, and for the read-only DMG installer volume, where Finder
#     can't render the Assets.car Liquid Glass icon.
# --minimum-deployment-target 26.0 is required to emit the Liquid Glass Assets.car
# (and is required at all, else actool fails to resolve the glyph layer).
ICON_NAME="laserpoint"   # basename of the .icon package and emitted .icns
ICON_SRC="Assets/$ICON_NAME.icon"
if [[ -d "$ICON_SRC" ]]; then
    echo "==> Compiling app icon (Liquid Glass)"
    xcrun actool "$ICON_SRC" \
        --compile "$APP_DIR/Contents/Resources" \
        --app-icon "$ICON_NAME" \
        --include-all-app-icons \
        --platform macosx \
        --minimum-deployment-target 26.0 \
        --output-partial-info-plist "$(mktemp)" >/dev/null
    # Fail loudly if actool didn't emit both artifacts (older Xcode/actool emits
    # only one, or none) — otherwise we'd silently ship a bundle with a missing
    # or degraded icon.
    if [[ ! -f "$APP_DIR/Contents/Resources/Assets.car" ]]; then
        echo "error: actool did not produce Assets.car (needs Xcode 26+)" >&2
        exit 1
    fi
    if [[ ! -f "$APP_DIR/Contents/Resources/$ICON_NAME.icns" ]]; then
        echo "error: actool did not produce $ICON_NAME.icns (needs Xcode 26+)" >&2
        exit 1
    fi
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

        # dmgbuild lays out the installer window (background + icon positions) by
        # writing the .DS_Store itself — no Finder/AppleScript, so it needs no
        # Automation permission and works headless in CI. Run it from a venv
        # since the system Python is externally managed (PEP 668).
        VENV=".build/dmg-venv"
        if [[ ! -x "$VENV/bin/dmgbuild" ]]; then
            echo "==> Setting up dmgbuild"
            python3 -m venv "$VENV"
            "$VENV/bin/pip" install --quiet --disable-pip-version-check dmgbuild
        fi

        # Icon positions must match the arrow in Assets/dmg-background.tiff (see
        # Assets/make-dmg-background.swift).
        SETTINGS="$(mktemp).py"
        cat > "$SETTINGS" <<PYEOF
app = "$APP_DIR"
files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {app: (170, 220), "Applications": (470, 220)}
background = "Assets/dmg-background.tiff"
window_rect = ((200, 120), (640, 420))
default_view = "icon-view"
icon_size = 128
format = "UDZO"
PYEOF

        rm -f "$DMG"
        "$VENV/bin/dmgbuild" -s "$SETTINGS" "$APP_NAME" "$DMG" >/dev/null
        rm -f "$SETTINGS"
        echo "==> Built $DMG"
        ;;
esac
