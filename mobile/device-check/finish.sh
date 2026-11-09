#!/usr/bin/env bash
# Writes out/report.md and out/verdict.txt from the build, the tour and Claude. A crash or a failed tour step makes it
# broken, and Claude's missing verdict no-verdict: each fails the job.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$OUT/claude"
[ -n "${DEVICE_UDID:-}" ] && bash "$here/phone-log.sh"
cd "$OUT" || exit 1
node "$here/crash.mjs" crashes > crash.txt
[ -s crash.txt ] || rm -f crash.txt
stopped=$(cat verdict.txt 2>/dev/null)
verdict=$stopped
reason=$(cat reason.txt 2>/dev/null)
failed=$([ -f tour.json ] && jq -r '[.[] | select(.passed | not) | .flow] | join(", ")' tour.json)
# An app that crashes is broken, whatever Claude or a step saw; tour.sh already stopped on a crash in the tour.
if [ -z "$verdict" ] && [ -f crash.txt ]; then verdict=broken; reason="The app crashed while Claude checked it."; fi
if [ -z "$verdict" ] && [ -n "$failed" ]; then verdict=broken; reason="A step of the tour failed: $failed."; fi
if [ -z "$verdict" ] && [ -f claude-skipped.txt ]; then
  verdict=could-not-check; reason="$(cat claude-skipped.txt). The fixed tour passed."
elif [ -z "$verdict" ]; then
  # steps.mjs writes claude/end.txt when Claude stopped before its final verdict: that is red, not could-not-check.
  verdict=$(head -n 1 claude/verdict.txt 2>/dev/null | tr -d '[:space:]')
  case "$verdict" in works | broken | could-not-check) ;; *) verdict=no-verdict ;; esac
  if [ -s claude/end.txt ] || [ "$verdict" = no-verdict ]; then
    verdict=no-verdict
    reason="$(cat claude/end.txt 2>/dev/null || echo 'Claude stopped with no verdict.') The fixed tour passed. See claude/steps.md."
  fi
fi
echo "$verdict" > verdict.txt
[ -n "$reason" ] && echo "$reason" > reason.txt

tour_line='"- \(.flow): \(if .passed then "passed" else "failed" end)'
tour_line+='\(if .passed and .tries == 2 then " on the second try" else "" end) (`\(.screenshot)`'
tour_line+='\(if .screenshot_live then ", the screen after the tour: the step left no picture" else "" end))"'
{
  echo "## iPhone check: $verdict"
  echo
  if [ -f crash.txt ]; then
    echo "### The app crashed"; echo; echo '```text'; cat crash.txt; echo '```'
    echo; echo "The crash reports are in \`crashes/\`."; echo
  fi
  device=$(cat device.txt 2>/dev/null)
  echo "Commit \`$(cat commit.txt 2>/dev/null)\`${device:+ on $device}."
  [ -n "$reason" ] && { echo; echo "$reason"; }
  echo
  echo "### Tour"
  echo
  if [ -f tour.json ]; then
    jq -r ".[] | $tour_line" tour.json
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
  [ -f claude/steps.md ] && { echo; echo "Each command Claude ran: \`claude/steps.md\`."; }
  # PASSED_BEFORE: the last check's link, then one scenario name per line (scripts/device-check.mjs --recheck).
  if [ -n "${PASSED_BEFORE:-}" ]; then
    # The next re-check reads this file to skip these names again.
    printf '%s\n' "$PASSED_BEFORE" > passed-before.txt
    echo; echo "### Passed in the last check"; echo
    echo "Claude did not try these again: they passed in [the last check]($(head -n 1 <<< "$PASSED_BEFORE"))."
    echo; tail -n +2 <<< "$PASSED_BEFORE" | sed '/^[[:space:]]*$/d; s/^/- /'
  fi
  if [ -f error.txt ]; then
    echo; echo "### Error"; echo; echo '```text'; cat error.txt; echo '```'
  fi
  [ -f run.mp4 ] && { echo; echo "Video: \`run.mp4\`."; }
} > report.md
cat report.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$verdict" != broken ] && [ "$verdict" != no-verdict ]
