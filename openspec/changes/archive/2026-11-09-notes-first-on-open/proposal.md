# Notes first when the app opens

**Status:** ready-to-ship
**Branch:** speed-up-phone-sync
**Open questions:** none

## Why

When you open the Relay Everything app, or come back to it, new notes from your other phones come in slowly. Before the app gets them, it first reads and sends all the health data, location points, calendar events and photos that the phone could not send in the background. iPhone gives the app little background time, so this work is often large. Also, if one health or photo upload fails, the app does not get new notes at all.

## What Changes

- **Notes come first.** When you open the app, come back to it, pull down the list, or tap **Sync now**, the app sends your own notes, then gets the new notes from your other phones. Only then does it read and send health, places, the calendar and photos. A new note no longer waits behind a large health upload.
  ```mermaid
  flowchart TD
    A["Open the app"] --> N["Send your notes"]
    N --> P["Get new notes"]
    P --> H["Health, places, photos"]
  ```

- **Syncing shows only for notes.** The **Syncing** line on Home shows while the app sends and gets notes. It stops when the notes are done, also while the app still sends health, places and photos behind it.

- **A failed health or photo upload does not stop notes.** New notes still come in when a health, place, calendar or photo upload fails. That data waits on the phone and goes on a later round, as now.

- **A new note goes before the rest.** If you write a note while the app sends health or photos, the app stops that work at its next upload, sends your note and gets new notes, then goes on with the rest.

- **The background round does the same.** When the phone runs the app in the background, it also sends notes and gets new notes before the other data, so a short background wake gets the notes through first.

## What the build needs

- **Nothing.** The change is in the phone app's code and tests, and the website page about notes.

## Decision log

**2026-11-09** — Asked whether to plan the fix that sends and gets notes first, then health, places and photos with no Syncing line, and lets a failed health or photo upload not block notes → chose *yes, ship it*.

**2026-11-09** — Assumed: a new note or a pull that comes while the app sends health or photos stops that work at its next upload, and a new round starts with notes, because otherwise the note waits behind the whole backlog again; data not sent waits on the phone and goes on the next round.

**2026-11-09** — Assumed: the background round (hourly task and iPhone wakes) also sends notes and gets new notes before private data, also when both go to Relay Everything, because a wake has only about 25 seconds and notes are what the person sees.

**2026-11-09** — Assumed: Home's sync state reports only notes; a failed health, place, calendar or photo upload to Relay Everything no longer turns it to *No signal*, because the state says whether your server has the notes from this phone, and a failed private upload to the webhook already shows on the Account page.

**2026-11-09** — Assumed: no change to how often iPhone runs the app in the background, because iPhone decides that and the app already asks for each kind of wake it can.

**2026-11-09** — Assumed (build): a refused key on a health, place, calendar or photo upload to Relay Everything still shows *Key refused* on Home, because a turned-off key also refuses the notes, and the existing test *a turned-off key shows refused when only photos are waiting* keeps its meaning; other failures there no longer change Home.

**2026-11-09** — Assumed (build): when the notes could not go, such as with no signal, the health, places, calendar and photos part runs in full and a new note does not stop it, because no round follows to send them; a stop also skips the reads still to come, not only the uploads.

**2026-11-09** — Assumed (build): Sign out and a server change wait for a pull that already reads (`_reading`), in place of the old `_pulling`, so nothing it read lands after the delete.

**2026-11-09** — Assumed (build): `pullNotes` starts the round and does not pass on an error the round throws, as every other `unawaited(sync())` caller in the app already does, because the pull's caller (pull to refresh, Sync now) only needs to know the notes part ended.

**2026-11-09** — Checkpoint: built and reviewed (review 0 after three test fixes); saved for CI's Flutter tests and both phone builds before the ship.

**2026-11-09** — Archive checkpoint: archived as `openspec/changes/archive/2026-11-09-notes-first-on-open`, saved on branch `speed-up-phone-sync` for the ship.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-note-sync`: on open, return, pull and Sync now, the phone sends its notes and gets new notes before it reads or sends health, places, calendar or photos, and a failure of those does not stop the notes.

## Impact

- `mobile/lib/controller.dart`: the round splits into a notes part (flush note routes, then pull) and a private part (health, calendar, history, stays, points, private flush, photos); the private part stops when a note or a pull waits; `pullNotes` returns after the notes part; the status comes only from the notes part.
- `mobile/lib/data/outbox.dart`, `mobile/lib/data/store.dart`: `flush` and `outbox` take a route filter, so notes and private data of one destination flush apart.
- `mobile/lib/sync/background.dart`: `backgroundRound` flushes note routes and pulls before it reads health and places.
- `mobile/test/`: controller and sync tests for the order, the stop and the status.
- `site/src/content/docs/app/your-notes.md`, `wiki/relay-phone-sync.md`: say that notes go first.
- Non-goals: more background time from iPhone; batching many uploads in one request; a new screen.
