#!/usr/bin/env bash
# Copies the app's crash reports since it opened to out/crashes/, so Claude can read a crash as it works. With
# `watch`, it copies each 5 s until it is stopped: iphone-open.sh starts it, the workflow stops it with the video.
set -uo pipefail
copy() {
  mkdir -p "$OUT/crashes"
  [ -f "$OUT/launch.log" ] || return 0
  find "$HOME/Library/Logs/DiagnosticReports" -name 'Runner*' -newer "$OUT/launch.log" -exec cp {} "$OUT/crashes/" \; 2>/dev/null
}
copy
while [ "${1:-}" = watch ]; do sleep 5; copy; done
exit 0
