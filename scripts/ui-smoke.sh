#!/usr/bin/env bash
# CI smoke test: launch the app straight into a scenario and take screenshots.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=build/smoke
mkdir -p "$OUT"
SCENARIO="${1:-controlled-departure}"

log stream --style compact --predicate 'subsystem == "uk.rttrainer.ATCTrainer"' > "$OUT/oslog.txt" 2>&1 &
LOGPID=$!

RT_AUTOSTART="$SCENARIO" RT_SKIP_PERMISSIONS=1 RT_DUMP_UI=1 \
  "build/RT Trainer.app/Contents/MacOS/ATCTrainer" > "$OUT/stdout.txt" 2>&1 &
APPPID=$!

for t in 3 8 15; do
  sleep $(( t - ${last:-0} )); last=$t
  screencapture -x "$OUT/screen-${t}s.png" || echo "screencapture failed"
  if kill -0 $APPPID 2>/dev/null; then echo "t=${t}s: app running"; else echo "t=${t}s: app NOT running"; fi
done

kill $APPPID 2>/dev/null; sleep 1; kill $LOGPID 2>/dev/null
cp ~/Library/Logs/DiagnosticReports/ATCTrainer* "$OUT/" 2>/dev/null || true
echo "--- stdout/stderr"; cat "$OUT/stdout.txt"
echo "--- os log"; cat "$OUT/oslog.txt"

