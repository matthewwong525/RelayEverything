#!/usr/bin/env bash
# Writes out/report.md and out/verdict.txt from the build, the tour and Claude. A failed tour step makes it broken.
set -uo pipefail
mkdir -p "$OUT/claude"
cd "$OUT" || exit 1
stopped=$(cat verdict.txt 2>/dev/null)
verdict=$stopped
reason=$(cat reason.txt 2>/dev/null)
failed=$([ -f tour.json ] && jq -r '[.[] | select(.passed | not) | .flow] | join(", ")' tour.json)
if [ -z "$verdict" ] && [ -n "$failed" ]; then verdict=broken; reason="A step of the fixed tour failed: $failed."; fi
if [ -z "$verdict" ]; then
  verdict=$(head -n 1 claude/verdict.txt 2>/dev/null | tr -d '[:space:]')
  case "$verdict" in
    works | broken | could-not-check) ;;
    *) verdict=could-not-check
       if [ -f claude-skipped.txt ]; then reason="Claude skipped: no key. The fixed tour passed."
       else reason="Claude gave no verdict. The fixed tour passed."; fi ;;
  esac
fi
echo "$verdict" > verdict.txt

{
  echo "## iPhone check: $verdict"
  echo
  device=$(cat device.txt 2>/dev/null)
  echo "Commit \`$(cat commit.txt 2>/dev/null)\`${device:+ on $device}."
  [ -n "$reason" ] && { echo; echo "$reason"; }
  echo
  echo "### Fixed tour"
  echo
  if [ -f tour.json ]; then
    jq -r '.[] | "- \(.flow): \(if .passed then "passed" else "failed" end) (`\(.screenshot)`)"' tour.json
  else
    echo "The tour did not run."
  fi
  echo
  echo "### Claude"
  echo
  if [ -f claude/report.md ]; then cat claude/report.md
  elif [ -f claude-skipped.txt ]; then cat claude-skipped.txt
  elif [ -n "$stopped" ]; then echo "Claude did not start."
  else echo "Claude gave no report."; fi
  if [ -f error.txt ]; then
    echo; echo "### Error"; echo; echo '```text'; cat error.txt; echo '```'
  fi
  [ -f run.mp4 ] && { echo; echo "Video: \`run.mp4\`."; }
} > report.md
cat report.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$verdict" != broken ]
