#!/usr/bin/env bash
# CI UI smoke test: launch the app, start scenarios, and OCR the screen to check the
# session view actually renders (regression test for a blank window after "Start scenario").
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=build/smoke
mkdir -p "$OUT"
APP_BIN="build/RT Trainer.app/Contents/MacOS/ATCTrainer"
FAILED=0

run_case() {
  local name="$1" expect="$2"; shift 2
  echo "=================== CASE $name (expect: $expect)"
  env RT_SKIP_PERMISSIONS=1 "$@" "$APP_BIN" > "$OUT/$name.txt" 2>&1 &
  local pid=$!
  sleep 7
  screencapture -x "$OUT/$name.png" || echo "screencapture failed"
  kill -0 $pid 2>/dev/null || { echo "FAIL: app exited"; FAILED=1; }
  kill $pid 2>/dev/null; sleep 2
  cat "$OUT/$name.txt"
  swift scripts/ocr.swift "$OUT/$name.png" 2>/dev/null > "$OUT/$name.ocr.txt"
  cat "$OUT/$name.ocr.txt"
  if grep -Eq "$expect" "$OUT/$name.ocr.txt"; then echo "PASS: $name"; else echo "FAIL: $name: '$expect' not on screen"; FAILED=1; fi
}

run_case intro "Start scenario" RT_SELECT=controlled-departure
run_case session-departure "PTT" RT_AUTOSTART=controlled-departure
run_case session-mayday "PTT" RT_AUTOSTART=mayday

cp ~/Library/Logs/DiagnosticReports/ATCTrainer* "$OUT/" 2>/dev/null || true
exit $FAILED
