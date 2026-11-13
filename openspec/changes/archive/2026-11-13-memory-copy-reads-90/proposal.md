# The WongStack memory copy reads 90 fact numbers at a time

**Status:** ready-to-ship
**Branch:** slippery-dragon
**Open questions:** none

## Why

The script that copies a WongStack memory into your Relay Everything space stopped on its first read from WongOS. It asks the old store for 200 fact numbers at a time, and that store takes at most 100 in one request. WongOS's copy on 2026-11-13 worked only with a temporary copy of the script set to 90.

## What Changes

- **The copy reads 90 numbers at a time.** It asks the old store for facts 1 to 90, then 91 to 180, and so on, below the store's limit of 100. It still sends them to your space 200 at a time, as before. A copy from a store with no such limit gives the same result as before.
  ```text
  Old store                 Your space
  1-90    ─┐
  91-180  ─┼─ read ──▶  1-200  ── send
  181-270 ─┘            201-400 ── send
  ```
- **The test store refuses big reads.** The test's stand-in for the old store now refuses a request for more than 100 numbers, as the real one does, so the same fault can't come back unseen. The automatic checks on each change now run this test too; today they skip it.
- **The how-to page says so.** The page that tells you how to move a WongStack memory in says the copy reads 90 numbers at a time, and why.

Non-goals: no change to the server, to how the space takes the facts, or to the plugin. WongOS's memory is in your space already (WongOS PR 328); this keeps the next copy from failing.

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-memory-store`: *A WongStack memory moves in once* also works from a source store that takes at most 100 numbers in one request.

## Impact

- `scripts/import-wongstack-memory.mjs`: a read size of 90 apart from the send size of 200.
- `scripts/import-wongstack-memory.test.mjs`: the source stand-in refuses a request of more than 100 numbers.
- `app/package.json`: the `test` script runs `scripts/import-wongstack-memory.test.mjs`, which no check ran before.
- `wiki/stack/relay-knowledge-web.md`, *Move a WongStack memory in*: one line on the read size.

## Decision log

- **2026-11-13** — Assumed: read 90 numbers a request, because the request set it, D1 takes at most 100 SQL variables, and WongOS's copy worked at 90.
- **2026-11-13** — Assumed: keep sending 200 facts a chunk, because the space's import route takes up to 200 and that worked on 2026-11-13.
- **2026-11-13** — Assumed: keep the stop after the same 10,000 empty numbers, not the same 50 empty ranges, because a range is now smaller and the old reach over a gap in the numbers should stay.
- **2026-11-13** — Assumed: no plugin version or site page change, because the script lives in `scripts/`, not in the plugin, and no site page names the read size.
- **2026-11-13** — Assumed: add the import test to the app's test run, because no CI check ran it, so the new limit in the test would guard nothing.
- **2026-11-13** — Check: `app/package.json` adds `../scripts/import-wongstack-memory.test.mjs` to the `test` script's `node --test` list and loosens nothing, because the import test ran in no check before.
- **2026-11-13** — Assumed: archived and saved inside /ship on branch `slippery-dragon`, because all tasks passed and the second look found nothing to fix.
