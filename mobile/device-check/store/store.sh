#!/usr/bin/env bash
# Takes the App Store screenshots on the booted simulator: makes the sample notes, then opens each screen with its
# flow and takes the whole screen at the device's own size. Writes $OUT/store/en-CA/<n>_<STORE_DEVICE>_<screen>.png.
set -euo pipefail
here=$(dirname "$0")
source "$here/../limit.sh"
shots="$OUT/store/en-CA"
mkdir -p "$shots" "$OUT/maestro"
screens=(home notes note search settings)

# Runs one flow, and once more if it fails or hangs: a first Maestro start can be slow on a new simulator.
run() {
  local flow=$1 end
  for _ in 1 2; do
    end=$(run_limited 300 "$OUT/maestro/store.log" maestro test "$here/$flow.yaml")
    [ "$end" = 0 ] && return 0
    echo "== $flow ended with $end" >> "$OUT/maestro/store.log"
  done
  echo "::error::The store flow $flow failed twice. The file store-log has Maestro's log."
  exit 1
}

# Apple's own look for store pictures: 9:41, full signal and a full battery.
xcrun simctl status_bar "$DEVICE_UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100
run sample-notes
for n in "${!screens[@]}"; do
  screen=${screens[$n]}
  run "$screen"
  sleep 2
  xcrun simctl io "$DEVICE_UDID" screenshot --type=png "$shots/$((n + 1))_${STORE_DEVICE}_${screen}.png"
done
ls -l "$shots"
