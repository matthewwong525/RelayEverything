#!/usr/bin/env bash
# Runs RelayWatchTests on an Apple Watch simulator on the newest watchOS the Mac has. Run it from mobile/ after
# `flutter build ios --config-only`; it keeps the log in $OUT/watch-tests.log and fails when a test fails.
#
# First it compiles the watch app and its tests for arm64_32, the 32-bit slice that a Series 4 to 8, an SE, an SE 2
# and the first Ultra run, where Int is 32 bits. Every watch simulator is 64-bit, so this compile is the only check
# that sees those watches: it finds a literal too large for a 32-bit Int, but it runs nothing, so a number that grows
# too large at run time is not found. It keeps the log in $OUT/watch-32bit.log and fails when the compile fails.
set -uo pipefail
mkdir -p "$OUT"
echo "Compiling RelayWatch and RelayWatchTests for arm64_32 (32-bit Apple Watch)"
if ! xcodebuild build-for-testing -workspace ios/Runner.xcworkspace -scheme RelayWatch \
  -destination 'generic/platform=watchOS' ARCHS=arm64_32 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$OUT/watch-32bit.log" | tail -n 40; then
  echo "::error::The watch app or its tests do not compile for the 32-bit Apple Watch (arm64_32): see watch-32bit.log."
  exit 1
fi
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
