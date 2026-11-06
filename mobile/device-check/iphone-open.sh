#!/usr/bin/env bash
# Boots an iPhone on the newest iOS the Mac has, installs the simulator build, starts the video and opens the app.
set -uo pipefail
here=$(dirname "$0")
app=mobile/build/ios/iphonesimulator/Runner.app
fail() { bash "$here/broken.sh" "$1" "${2:-}"; exit 0; }

pick=$(xcrun simctl list devices available -j | jq -r '
  .devices | to_entries
  | map(select(.key | test("SimRuntime\\.iOS-[0-9-]+$")))
  | sort_by(.key | capture("iOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber))
  | (last // {value: []}).value | map(select(.name | startswith("iPhone"))) | last // empty
  | "\(.udid)\t\(.name)"')
[ -n "$pick" ] || fail "The Mac has no iPhone simulator."
udid=${pick%%$'\t'*}
echo "${pick#*$'\t'}" > "$OUT/device.txt"

xcrun simctl bootstatus "$udid" -b > "$OUT/boot.log" 2>&1 || fail "The iPhone simulator does not start." "$OUT/boot.log"
xcrun simctl install "$udid" "$app" > "$OUT/install.log" 2>&1 || fail "The app does not install on the iPhone." "$OUT/install.log"
xcrun simctl io "$udid" recordVideo --codec=h264 --force "$OUT/run.mp4" > "$RUNNER_TEMP/video.log" 2>&1 &
echo $! > "$RUNNER_TEMP/video.pid"
xcrun simctl launch "$udid" "$APP_ID" > "$OUT/launch.log" 2>&1 || fail "The app does not open on the iPhone." "$OUT/launch.log"
echo "DEVICE_UDID=$udid" >> "$GITHUB_ENV"
echo "ok=true" >> "$GITHUB_OUTPUT"
