#!/usr/bin/env bash
# CI smoke test: launch the app in several configurations and OCR what is on screen.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=build/smoke
mkdir -p "$OUT"
SCENARIO="${1:-controlled-departure}"
APP_BIN="build/RT Trainer.app/Contents/MacOS/ATCTrainer"

run_case() {
  local name="$1"; shift
  echo "=================== CASE $name"
  env RT_SKIP_PERMISSIONS=1 "$@" "$APP_BIN" > "$OUT/$name.txt" 2>&1 &
  local pid=$!
  sleep 7
  screencapture -x "$OUT/$name.png" || echo "screencapture failed"
  kill -0 $pid 2>/dev/null && echo "app running" || echo "app NOT running"
  kill $pid 2>/dev/null; sleep 2
  echo "--- output"; cat "$OUT/$name.txt"
  echo "--- OCR"; swift scripts/ocr.swift "$OUT/$name.png" 2>/dev/null || true
}

run_case intro RT_SELECT="$SCENARIO"
run_case session RT_AUTOSTART="$SCENARIO"
for v in nofeedback nocontrols notranscript nobriefing; do
  run_case "$v" RT_AUTOSTART="$SCENARIO" RT_VARIANT="$v"
done
cp ~/Library/Logs/DiagnosticReports/ATCTrainer* "$OUT/" 2>/dev/null || true
