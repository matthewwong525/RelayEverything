#!/usr/bin/env bash
# Writes Claude's prompt: the shared brief, the device's own lines ($1), and what to check. Outputs text and model.
set -euo pipefail
here=$(dirname "$0")
if ! [[ "$MODEL" =~ ^claude-[a-z0-9-]+$ ]]; then echo "::error::model must be a Claude model ID."; exit 1; fi
mkdir -p "$OUT/claude"

what() {
  if [ -n "${SCENARIOS:-}" ]; then printf '%s\n' "$SCENARIOS"; return; fi
  local specs
  specs=$(grep -rlis -e 'phone app' -e 'iphone' -e 'mobile/' openspec/changes --include=spec.md | grep -v '/archive/' || true)
  if [ -n "$specs" ]; then
    echo "No scenarios were given. Read these specs, and check each scenario the phone app can show:"
    sed 's/^/- /' <<< "$specs"
  else
    echo "No scenarios were given, and no open change names the phone app. Check the main screens:"
    echo "the notes list, search, a new note, a voice note from holding New note, and Settings."
  fi
}

prompt=$(
  cat "$here/brief.md"; echo
  cat "$1"; echo
  echo "## What to check"; echo
  echo "Commit: $(cat "$OUT/commit.txt")${PR:+. Pull request: #$PR}."; echo
  what
)
end="BRIEF_$(openssl rand -hex 8)"
{ echo "text<<$end"; echo "$prompt"; echo "$end"; echo "model=$MODEL"; } >> "$GITHUB_OUTPUT"
