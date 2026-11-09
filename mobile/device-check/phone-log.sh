#!/usr/bin/env bash
# Keeps the iPhone's log for the app, Shortcuts and App Intents, and the app's crash reports, so a step that failed
# with no words on the screen shows why.
set -uo pipefail
xcrun simctl spawn booted log show --last 60m --style compact --info --debug --predicate \
  'process == "Runner" OR process CONTAINS[c] "shortcut" OR process == "linkd" OR subsystem BEGINSWITH "com.apple.appintents" OR subsystem BEGINSWITH "com.apple.link"' \
  2>&1 | tail -n 30000 > "$OUT/phone.log"
bash "$(dirname "$0")/crashes.sh"
exit 0
