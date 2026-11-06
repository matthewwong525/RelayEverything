#!/usr/bin/env bash
# Ends the check as broken, with the reason and the end of the log that shows why. Claude does not start.
set -euo pipefail
echo broken > "$OUT/verdict.txt"
echo "$1" > "$OUT/reason.txt"
if [ -n "${2:-}" ] && [ -f "$2" ]; then tail -n 60 "$2" > "$OUT/error.txt"; fi
