#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="BlackBar"
BUILD_DIR="$ROOT_DIR/.build/release"
APP_DIR="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"
python3 "$ROOT_DIR/scripts/generate_app_icon.py"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/AppBundle/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

if [[ -f "$ROOT_DIR/AppBundle/AppIcon.icns" ]]; then
    cp "$ROOT_DIR/AppBundle/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

if [[ -f "$ROOT_DIR/image.png" ]]; then
    cp "$ROOT_DIR/image.png" "$RESOURCES_DIR/image.png"
fi

echo "Created $APP_DIR"
