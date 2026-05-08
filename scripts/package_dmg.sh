#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BlackBar"
BUILD_DIR="$ROOT_DIR/.build/release"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
STAGING_DIR="$(mktemp -d "$ROOT_DIR/.build/dmg-staging.XXXXXX")"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cleanup() {
    rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cd "$ROOT_DIR"
python3 "$ROOT_DIR/scripts/generate_app_icon.py"
swift build -c release

mkdir -p "$DIST_DIR" "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$ROOT_DIR/AppBundle/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/AppBundle/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/image.png" ]]; then
    cp "$ROOT_DIR/image.png" "$RESOURCES_DIR/image.png"
fi

rm -f "$DMG_PATH"
rm -rf "$DIST_DIR/$APP_NAME.app"

create-dmg \
  --volname "$APP_NAME" \
  --window-size 620 360 \
  --icon-size 128 \
  --icon "$APP_NAME.app" 160 170 \
  --hide-extension "$APP_NAME.app" \
  --app-drop-link 460 170 \
  "$DMG_PATH" \
  "$STAGING_DIR"

echo "Created $DMG_PATH"
