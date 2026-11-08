#!/usr/bin/env bash
# Picks an iPhone on the newest iOS the Mac has and starts it in the background, so it boots while the app builds.
# Sets DEVICE_UDID; iphone-open.sh waits for it.
set -uo pipefail
here=$(dirname "$0")
mkdir -p "$OUT"
pick=$(xcrun simctl list devices available -j | jq -r '
  .devices | to_entries
  | map(select(.key | test("SimRuntime\\.iOS-[0-9-]+$")))
  | sort_by(.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber))
  | (last // {value: []}).value | map(select(.name | startswith("iPhone"))) | last // empty
  | "\(.udid)\t\(.name)"')
if [ -z "$pick" ]; then bash "$here/broken.sh" "The Mac has no iPhone simulator."; exit 0; fi
udid=${pick%%$'\t'*}
echo "${pick#*$'\t'}" > "$OUT/device.txt"
xcrun simctl boot "$udid" > "$OUT/boot.log" 2>&1 &
echo "DEVICE_UDID=$udid" >> "$GITHUB_ENV"
echo "ok=true" >> "$GITHUB_OUTPUT"
