# Design: the waiting count counts notes

## Context

`RelayController` sets `waiting` from `store.waiting()` (`mobile/lib/data/store.dart`), which is `SELECT count(*) FROM outbox`. The outbox holds every send: `notes`, `note.update`, `note.pin`, `note.delete`, `note.recover` (each body has `clientId`), `attachment` (body has `noteClientId`), and `health`, `nights`, `stays`, `calendar`, location and photo batches. Only `SyncLine.stateOf` in `mobile/lib/screens/timeline.dart` reads `relay.waiting`, under the titles of Home and the notes list. Health, places and the calendar have their own `SendState.waiting` counts for their pages.

## Goals / Non-Goals

**Goals:** the number is the count of distinct notes with any waiting send. **Non-goals:** changing when the line shows, or the per-page counts.

## Decisions

### Count distinct notes in the note routes

`waiting()` becomes `SELECT count(DISTINCT coalesce(json_extract(body, '$.clientId'), json_extract(body, '$.noteClientId'))) FROM outbox WHERE route IN ('notes', noteUpdate, notePin, noteDelete, noteRecover, 'attachment')`, with the route names from the constants. SQLite's JSON functions are built into the phone's SQLite. A row with neither key does not count. The name `waiting()` stays; its comment says *waiting notes*.

## Risks / Trade-offs

- **A send for a note waits behind health data.** The line then shows no number while health sends. The pages for health, places and the calendar still show their own counts.

## Testing

`store_test.dart`: a note with two files and a change counts 1; two notes count 2; health, stays and calendar rows count 0. `screens_test.dart` keeps its *1 waiting* tests.

## Decision log

- **2026-11-16** — Asked: what next after recordings as attachments went live → chose fix the waiting count.
- **2026-11-16** — Assumed: health, places, calendar and photo data leave the count, because the spec already says the number is the notes waiting, and those have their own counts on their pages.
- **2026-11-16** — Assumed: a waiting pin, delete or recover counts its note, because the person still has that note's change waiting.
- **2026-11-16** — Assumed: built inline with no separate review helper, because the change is one query and three tests.
- **2026-11-16** — Asked: the device check broke in the recording-card step, which this change does not touch, and could not show the count on a signed-out test phone → chose publish, fix the check later.
- **2026-11-16** — Archive checkpoint: archived at `openspec/changes/archive/2026-11-16-waiting-notes-count`; the spec scenarios joined `openspec/specs/relay-brand/spec.md`.
