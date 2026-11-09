#!/usr/bin/env bash
# The fixed tour, then the check's extra flows ($EXTRA_FLOWS, names split by spaces), in one Maestro run with no AI.
# Each flow that failed runs once more, alone, after its driver and the app stop. ok=true only when each flow passed.
set -uo pipefail
here=$(dirname "$0")
source "$here/limit.sh"
read -ra extra <<< "${EXTRA_FLOWS:-}"
flows=(timeline new-note note-styles settings ${extra[@]+"${extra[@]}"})
# A second try starts Maestro's driver again (up to 180 s) before its flow, which took up to 170 s on a slow Mac.
retry_limit=${RETRY_LIMIT:-360}
mkdir -p "$OUT/tour" "$OUT/maestro/retry"
# Maestro runs every flow in the order given, also after one fails, and writes one JUnit test case per flow.
files=()
for flow in "${flows[@]}"; do files+=("$here/flows/$flow.yaml"); done
maestro test --format junit --output "$OUT/maestro/tour.xml" --test-output-dir "$OUT/maestro" "${files[@]}" \
  > "$OUT/maestro/tour.log" 2>&1

failed=$(node "$here/tour-json.mjs" "$OUT" "${flows[@]}" | jq -r '.[] | select(.passed | not) | .flow')
for flow in $failed; do
  echo "== $flow: second try" >> "$OUT/maestro/retry.log"
  pkill -TERM -f 'maestro-driver' 2>/dev/null
  xcrun simctl terminate booted "$APP_ID" > /dev/null 2>&1
  sleep 3
  : > "$OUT/maestro/retry/$flow.xml"
  end=$(run_limited "$retry_limit" "$OUT/maestro/retry.log" maestro test --format junit \
    --output "$OUT/maestro/retry/$flow.xml" --test-output-dir "$OUT/maestro/retry/$flow" "$here/flows/$flow.yaml")
  [ "$end" = hung ] && echo "The second try ran over $retry_limit s and was stopped." >> "$OUT/maestro/retry.log"
  # An app that does not open twice fails every later step too: their second tries would only add time.
  [ "$flow" = timeline ] && [ "$end" != 0 ] && break
done
node "$here/tour-json.mjs" "$OUT" "${flows[@]}" > "$OUT/tour.json"

# A flow whose tries both left no picture gets the screen as it is now, and tour.json says so.
for flow in $(jq -r '.[] | select(.screenshot_live) | .flow' "$OUT/tour.json"); do
  xcrun simctl io booted screenshot "$OUT/tour/$flow.png" > /dev/null 2>&1
done

bash "$here/crashes.sh"
node "$here/crash.mjs" "$OUT/crashes" > "$OUT/crash.txt"
[ -s "$OUT/crash.txt" ] || rm -f "$OUT/crash.txt"

broken=$(jq -r '[.[] | select(.passed | not) | .flow] | join(", ")' "$OUT/tour.json")
log="$OUT/maestro/tour.log"
[ -s "$OUT/maestro/retry.log" ] && log="$OUT/maestro/retry.log"
if [ -f "$OUT/crash.txt" ]; then
  bash "$here/broken.sh" "The app crashed during the tour.${broken:+ A step failed on both tries: $broken.}" "$log"
elif [ "$(jq -r '.[0].passed' "$OUT/tour.json")" != true ]; then
  bash "$here/broken.sh" "The app does not open on the iPhone: the timeline step failed on both tries." "$log"
elif [ -n "$broken" ]; then
  bash "$here/broken.sh" "A step of the tour failed on both tries: $broken." "$log"
else
  echo "ok=true" >> "$GITHUB_OUTPUT"
fi
