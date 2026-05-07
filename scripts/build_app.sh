#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build --disable-sandbox

BIN_DIR="$(swift build --disable-sandbox --show-bin-path)"
APP_DIR="$ROOT_DIR/dist/MacCompanion.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_DIR/MacCompanion" "$APP_DIR/Contents/MacOS/MacCompanion"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/Resources/MacCompanion.icns" "$APP_DIR/Contents/Resources/MacCompanion.icns"

chmod +x "$APP_DIR/Contents/MacOS/MacCompanion"

echo "$APP_DIR"
