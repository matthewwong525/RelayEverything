#!/usr/bin/env bash
# Runs RelayWatchTests on an Apple Watch simulator on the newest watchOS the Mac has. Run it from mobile/ after
# `flutter build ios --config-only`; it keeps the log in $OUT/watch-tests.log and fails when a test fails.
set -uo pipefail
mkdir -p "$OUT"
udid=$(xcrun simctl list devices available -j | jq -r '
  .devices | to_entries
  | map(select(.key | test("SimRuntime\\.watchOS-[0-9-]+$")))
  | sort_by(.key | capture("watchOS-(?<v>[0-9-]+)$").v | split("-") | map(tonumber))
  | (last // {value: []}).value | last // empty | .udid')
if [ -z "$udid" ]; then
  echo "::error::The Mac has no Apple Watch simulator, so the watch tests did not run." | tee "$OUT/watch-tests.log"
  exit 1
fi
xcodebuild test -workspace ios/Runner.xcworkspace -scheme RelayWatch -destination "id=$udid" \
  -only-testing:RelayWatchTests 2>&1 | tee "$OUT/watch-tests.log" | tail -n 40
