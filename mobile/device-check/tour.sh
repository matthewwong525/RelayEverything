#!/usr/bin/env bash
# The fixed tour: the flows in one Maestro run, one screenshot each, and out/tour.json. It uses no AI.
set -uo pipefail
here=$(dirname "$0")
flows=(timeline new-note note-styles settings)
mkdir -p "$OUT/tour" "$OUT/maestro"
# Maestro runs every flow in the order given, also after one fails, and writes one JUnit test case per flow.
files=()
for flow in "${flows[@]}"; do files+=("$here/flows/$flow.yaml"); done
maestro test --format junit --output "$OUT/maestro/tour.xml" --test-output-dir "$OUT/maestro" "${files[@]}" \
  > "$OUT/maestro/tour.log" 2>&1
node "$here/tour-json.mjs" "$OUT/maestro/tour.xml" "${flows[@]}" > "$OUT/tour.json"

for flow in "${flows[@]}"; do
  shot="$OUT/tour/$flow.png"
  # A failed flow never reaches its takeScreenshot: Maestro's picture of the failed step stands in for it.
  found=$(find "$OUT/maestro" -name "$flow.png" 2>/dev/null | head -n 1)
  [ -n "$found" ] || found=$(find "$OUT/maestro" -name "screenshot-*($flow).png" 2>/dev/null | head -n 1)
  if [ -n "$found" ]; then cp "$found" "$shot"; else xcrun simctl io booted screenshot "$shot" > /dev/null 2>&1; fi
done

if [ "$(jq -r '.[0].passed' "$OUT/tour.json")" != true ]; then
  bash "$here/broken.sh" "The app does not open on the iPhone: the timeline step failed." "$OUT/maestro/tour.log"
else
  echo "ok=true" >> "$GITHUB_OUTPUT"
fi
