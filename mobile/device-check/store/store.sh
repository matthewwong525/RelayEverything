#!/usr/bin/env bash
# Takes the App Store screenshots on the booted simulator: makes the sample notes, then opens each screen, whose flow
# ends with a takeScreenshot at the device's own size. Writes $OUT/store/en-CA/<n>_<STORE_DEVICE>_<screen>.png.
set -uo pipefail
here=$(dirname "$0")
source "$here/../limit.sh"
shots="$OUT/store/en-CA"
runs="$OUT/maestro/store"
log="$OUT/maestro/store.log"
mkdir -p "$shots" "$runs"
screens=(home notes note search settings)

# The picture a screen's flow took in any run so far, or nothing.
picture() { find "$runs" -name "$1.png" 2>/dev/null | head -n 1; }

# Apple's own look for store pictures: 9:41, full signal and a full battery.
xcrun simctl status_bar "$DEVICE_UDID" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
  --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100

# Each Maestro start costs its driver up to 3 minutes, so every flow goes in one run, in this order.
files=("$here/sample-notes.yaml")
for screen in "${screens[@]}"; do files+=("$here/$screen.yaml"); done
end=$(run_limited 1200 "$log" maestro test --test-output-dir "$runs/all" "${files[@]}")
echo "== one run of every flow ended with $end" >> "$log"

# A screen with no picture runs once more alone. The notes stay on the simulator, so its flow needs no others.
missing=()
for screen in "${screens[@]}"; do [ -n "$(picture "$screen")" ] || missing+=("$screen"); done
if [ "${#missing[@]}" -eq "${#screens[@]}" ]; then missing=(sample-notes "${screens[@]}"); fi
for flow in ${missing[@]+"${missing[@]}"}; do
  pkill -TERM -f 'maestro-driver' 2>/dev/null
  sleep 3
  end=$(run_limited 480 "$log" maestro test --test-output-dir "$runs/$flow" "$here/$flow.yaml")
  echo "== $flow alone ended with $end" >> "$log"
done

failed=()
for n in "${!screens[@]}"; do
  screen=${screens[$n]}
  found=$(picture "$screen")
  if [ -n "$found" ]; then cp "$found" "$shots/$((n + 1))_${STORE_DEVICE}_${screen}.png"; else failed+=("$screen"); fi
done
ls -l "$shots"
if [ "${#failed[@]}" -gt 0 ]; then
  echo "::error::No picture of: ${failed[*]}. The file store-log-$STORE_DEVICE has Maestro's log and pictures."
  exit 1
fi
