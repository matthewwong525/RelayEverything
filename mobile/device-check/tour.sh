#!/usr/bin/env bash
# The fixed tour: each flow in order, one screenshot each, and out/tour.json. It uses no AI.
set -uo pipefail
here=$(dirname "$0")
mkdir -p "$OUT/tour" "$OUT/maestro"
results='[]'
for flow in timeline new-note settings; do
  shot="$OUT/tour/$flow.png"
  if maestro test --test-output-dir "$OUT/maestro/$flow" "$here/flows/$flow.yaml" > "$OUT/maestro/$flow.log" 2>&1; then
    passed=true
  else
    passed=false
  fi
  # A failed flow never reaches its takeScreenshot, so the picture shows the screen it stopped on.
  found=$(find "$OUT/maestro/$flow" -name "$flow.png" 2>/dev/null | head -n 1)
  if [ -n "$found" ]; then cp "$found" "$shot"; else xcrun simctl io booted screenshot "$shot" > /dev/null 2>&1; fi
  results=$(jq -c --arg flow "$flow" --argjson passed "$passed" --arg shot "tour/$flow.png" \
    '. + [{flow: $flow, passed: $passed, screenshot: $shot}]' <<< "$results")
done
echo "$results" > "$OUT/tour.json"

if [ "$(jq -r '.[0].passed' "$OUT/tour.json")" != true ]; then
  bash "$here/broken.sh" "The app does not open on the iPhone: the timeline step failed." "$OUT/maestro/timeline.log"
else
  echo "ok=true" >> "$GITHUB_OUTPUT"
fi
