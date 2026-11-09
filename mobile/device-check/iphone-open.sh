#!/usr/bin/env bash
# Waits for the iPhone that iphone-boot.sh started, installs the simulator build, starts the video, opens the app and
# starts copying its crash reports.
set -uo pipefail
here=$(dirname "$0")
app=mobile/build/ios/iphonesimulator/Runner.app
fail() { bash "$here/broken.sh" "$1" "${2:-}"; exit 0; }

xcrun simctl bootstatus "$DEVICE_UDID" -b >> "$OUT/boot.log" 2>&1 || fail "The iPhone simulator does not start." "$OUT/boot.log"
xcrun simctl install "$DEVICE_UDID" "$app" > "$OUT/install.log" 2>&1 || fail "The app does not install on the iPhone." "$OUT/install.log"
xcrun simctl io "$DEVICE_UDID" recordVideo --codec=h264 --force "$OUT/run.mp4" > "$RUNNER_TEMP/video.log" 2>&1 &
echo $! > "$RUNNER_TEMP/video.pid"
launched=true
xcrun simctl launch "$DEVICE_UDID" "$APP_ID" > "$OUT/launch.log" 2>&1 || launched=false
bash "$here/crashes.sh" watch > /dev/null 2>&1 &
echo $! > "$RUNNER_TEMP/crashes.pid"
$launched || fail "The app does not open on the iPhone." "$OUT/launch.log"
echo "ok=true" >> "$GITHUB_OUTPUT"
