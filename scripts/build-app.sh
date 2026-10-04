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

# Ad-hoc signature so privacy permissions (TCC) attach to the app.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
if [[ "${1:-}" == "--open" ]]; then
  open "$APP"
fi
