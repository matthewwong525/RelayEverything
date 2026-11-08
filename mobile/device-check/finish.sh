#!/usr/bin/env bash
# Writes out/report.md and out/verdict.txt from the build, the tour and Claude. A failed tour step makes it broken, and
# Claude's missing verdict no-verdict: both fail the job.
set -uo pipefail
mkdir -p "$OUT/claude"
[ -n "${DEVICE_UDID:-}" ] && bash "$(dirname "$0")/phone-log.sh"
cd "$OUT" || exit 1
stopped=$(cat verdict.txt 2>/dev/null)
verdict=$stopped
reason=$(cat reason.txt 2>/dev/null)
failed=$([ -f tour.json ] && jq -r '[.[] | select(.passed | not) | .flow] | join(", ")' tour.json)
if [ -z "$verdict" ] && [ -n "$failed" ]; then verdict=broken; reason="A step of the fixed tour failed: $failed."; fi
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
  [ -f claude/steps.md ] && { echo; echo "Each command Claude ran: \`claude/steps.md\`."; }
  if [ -f error.txt ]; then
    echo; echo "### Error"; echo; echo '```text'; cat error.txt; echo '```'
  fi
  [ -f run.mp4 ] && { echo; echo "Video: \`run.mp4\`."; }
} > report.md
cat report.md >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
[ "$verdict" != broken ] && [ "$verdict" != no-verdict ]
