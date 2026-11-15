#!/usr/bin/env bash
# Takes the App Store screenshot of the watch app on the largest Apple Watch simulator on the newest watchOS. Run it
# from mobile/ after `flutter build ios --simulator --debug --config-only`. Writes $OUT/store/en-CA/1_watch_record.png.
set -euo pipefail
shots="$OUT/store/en-CA"
mkdir -p "$shots"
pick=$(xcrun simctl list devices available -j | jq -r '
  .devices | to_entries
  | map(select(.key | test("SimRuntime\\.watchOS-[0-9-]+$")))
  | sort_by(.key | capture("watchOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber))
  | (last // {value: []}).value | (map(select(.name | test("Ultra"))) | last) // last // empty
  | "\(.udid)\t\(.name)"')
if [ -z "$pick" ]; then echo "::error::The Mac has no Apple Watch simulator."; exit 1; fi
udid=${pick%%$'\t'*}
echo "Apple Watch: ${pick#*$'\t'}"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b

xcodebuild build -workspace ios/Runner.xcworkspace -scheme RelayWatch -destination "id=$udid" \
  -derivedDataPath build/watch CODE_SIGNING_ALLOWED=NO 2>&1 | tee "$OUT/watch-build.log" | tail -n 20
app=$(find build/watch/Build/Products -maxdepth 2 -name RelayWatch.app -path '*watchsimulator*' | head -n 1)
if [ -z "$app" ]; then echo "::error::The watch app did not build for the simulator: see watch-build.log."; exit 1; fi
xcrun simctl install "$udid" "$app"
# The app records as soon as it opens, so it gets the microphone first and shows no question in the picture.
xcrun simctl privacy "$udid" grant microphone "$WATCH_APP_ID"
xcrun simctl status_bar "$udid" override --time 9:41 2>/dev/null || true
xcrun simctl launch "$udid" "$WATCH_APP_ID"
sleep 8
xcrun simctl io "$udid" screenshot --type=png "$shots/1_watch_record.png"
ls -l "$shots"
