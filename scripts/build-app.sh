#!/usr/bin/env bash
# Builds "RT Trainer.app" from the Swift package. A real .app bundle (with Info.plist) is required
# for macOS to grant microphone and speech-recognition access.
#
#   scripts/build-app.sh          # release build into build/RT Trainer.app
#   scripts/build-app.sh --open   # build and launch
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/RT Trainer.app"

swift build -c "$CONFIG" --product ATCTrainer
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ATCTrainer" "$APP/Contents/MacOS/ATCTrainer"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Bundle every scenario pack so the app works offline.
cp -R scenario-packs "$APP/Contents/Resources/scenario-packs"

# App icon: build every size macOS needs from the 1024 px master (Resources/AppIcon.png).
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

# Ad-hoc signature so privacy permissions (TCC) attach to the app.
codesign --force --sign - --timestamp=none "$APP"
# Nudge Finder/Dock to pick up a changed icon.
touch "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP"
fi
