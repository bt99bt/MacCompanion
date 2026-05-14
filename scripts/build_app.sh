#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/private/tmp/maccompanion-clang-cache}"

swift build --disable-sandbox

HOST_ARCH="$(uname -m)"
BIN_DIR="$ROOT_DIR/.build/${HOST_ARCH}-apple-macosx/debug"
APP_DIR="$ROOT_DIR/dist/MacCompanion.app"
ICON_SRC="$ROOT_DIR/Resources/MacCompanionIcon.svg"
ICON_WORK_DIR="$ROOT_DIR/.build/generated-icons"
ICONSET_DIR="$ICON_WORK_DIR/MacCompanion.iconset"
ICON_PNG="$ICON_WORK_DIR/MacCompanionIcon.png"
ICON_ICNS="$ICON_WORK_DIR/MacCompanion.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
rm -rf "$ICON_WORK_DIR"
mkdir -p "$ICONSET_DIR"

qlmanage -t -s 1024 -o "$ICON_WORK_DIR" "$ICON_SRC" >/dev/null
mv "$ICON_WORK_DIR/MacCompanionIcon.svg.png" "$ICON_PNG"

sips -z 16 16 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_PNG" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_ICNS"

cp "$BIN_DIR/MacCompanion" "$APP_DIR/Contents/MacOS/MacCompanion"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ICON_ICNS" "$APP_DIR/Contents/Resources/MacCompanion.icns"
if [ -d "$ROOT_DIR/server/images" ]; then
  mkdir -p "$APP_DIR/Contents/Resources/WifiCodeServerImages"
  cp "$ROOT_DIR"/server/images/*.tar "$APP_DIR/Contents/Resources/WifiCodeServerImages/" 2>/dev/null || true
fi
if [ -d "$ROOT_DIR/server/deploy" ]; then
  mkdir -p "$APP_DIR/Contents/Resources/WifiCodeServerDeploy"
  cp "$ROOT_DIR"/server/deploy/*.sh "$APP_DIR/Contents/Resources/WifiCodeServerDeploy/"
fi

chmod +x "$APP_DIR/Contents/MacOS/MacCompanion"
codesign --force --deep --sign - "$APP_DIR" >/dev/null
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

echo "$APP_DIR"
