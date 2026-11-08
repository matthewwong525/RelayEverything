# Delete a note from the phone app, everywhere

**Status:** planned; the build waits for *Your notes on every phone* (PR #64) to be published
**Branch:** potent-fox
**Open questions:** none

## Why

Today you can't delete a note on the phone. Only an empty note goes, and a note you already sent stays on your page and with your webhooks. With your notes on every phone, a note deleted on one phone would come back at the next sync. You need one *Delete* that removes the note everywhere, as in Apple Notes.

## What Changes

- **Delete is in the note's ⋯ menu.** Open a note, tap ⋯, then *Delete*. The note page closes, and the list shows *Note deleted* with *Undo* for a few seconds. There is no "Are you sure?" box.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Notes</button><span class="grow"/><button class="btn-ghost">⇪</button><button class="btn-ghost">⋯</button></div>
    <div class="row"><span class="grow"/><div class="card col gap"><span>Copy</span><span class="sep"/><span class="danger">Delete</span></div></div>
    <h3>Call the dentist</h3>
    <span>Ask about the 14th, after 3 pm.</span>
  </div>
  ```
  The phone app can't run on this computer, so this is a sketch, not a picture.
- **Swipe left on a note to delete it.** In any notes list, swipe a note to the left: a red bin shows behind it, and a full swipe deletes it. *Undo* shows the same way.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Notes</h3><span class="grow"/><button class="btn-ghost">⋯</button></div>
    <span class="muted">Today</span>
    <div class="card col"><b>Flight to Lisbon, seat 14A</b><span class="muted">8:02 · Email</span></div>
    <div class="row gap"><div class="card col grow"><b>Ideas for the ring app</b><span class="muted">7:15</span></div><span class="tag danger">🗑 Delete</span></div>
    <span class="grow"/>
    <div class="card row gap"><span class="grow">Note deleted</span><button class="btn-ghost">Undo</button></div>
  </div>
  ```
- **A deleted note goes away everywhere.** After the *Undo* time ends, the phone tells your Relay Everything space. The space deletes the note, its files and its recording. The note leaves your page, your AI apps, and your other phones at their next sync. Each webhook gets a *note deleted* message with the note's id. A note that never left the phone is only deleted on the phone. This can't be undone after the *Undo* time.
  ```mermaid
  sequenceDiagram
    participant A as iPhone
    participant S as Space
    participant B as Pixel
    participant W as Webhooks
    A->>S: Delete, after Undo
    S-->>W: note.deleted
    S-->>B: Gone at sync
  ```
- **An emptied note goes too.** Delete every word of a note with no files and leave it: it is deleted everywhere, with *Undo*, as Apple Notes does. Today a sent copy keeps its last words on your page.
- **It works when you are offline and with your own webhook.** A delete made offline, or with sending off, waits on the phone and goes when sending is on again, so the note never comes back. With *My own webhook*, the phone sends *note deleted* to your webhook.
  | Setting when you delete | What happens |
  |---|---|
  | Relay Everything | Gone from your page, other phones, and every webhook |
  | My own webhook | Your webhook gets *note deleted* |
  | Sending off | Gone from the phone now; the rest when sending is on again |

Non-goals: a *Delete* button on the web page, a *Recently Deleted* folder, deleting through the web API or an AI app, and deleting health, places, calendar or photos.

## What the build needs

- **Your notes on every phone, published first**: Ready, nothing from you. *Sync notes across phones* is in its last checks in its own chat. A phone-only delete would come back at the next sync, so the build's first step waits until it is published.
- **Phone app UI fixes**: Ready, nothing from you. The build does not wait for it. *Delete* goes in the note page's ⋯ menu as it is on `main` when the build starts.
- **Keys, accounts and packages**: Ready. Nothing new is needed. There are no real phone pictures, because this computer can't run the phone app.

## Capabilities

### New Capabilities
- `relay-note-deleting`: a person deletes a note on the phone from its ⋯ menu or with a swipe, with a short *Undo*; the server deletes it, its files and recording; other phones drop it at their next sync; webhooks get `note.deleted`; a delete waits on the phone while offline or with sending off; a phone's own webhook gets `note.deleted` too.

### Modified Capabilities
- `relay-note-editing`: a note left with no words and no files is deleted everywhere, with *Undo*, not only on the phone.
- `relay-device-keys`: a phone key may delete any note in its person's space; it still deletes nothing else. Written against the spec as *sync-notes-across-phones* leaves it (task 1.1).

## Impact

- Space migration `0012_note_deletes.sql`: `relay_note_changes` rebuilt without its foreign key and with a `deleted` mark, so a deleted note keeps a row at a new change number; a trigger on `relay_notes` deletes.
- Server, in `app/worker/apps/relay/`: a new `delete-note.ts` (`DELETE notes`, by `id` or `clientId`, for a phone key); `caller.ts` lets a phone reach it; `note-sync.ts` and `queries.ts` return deleted ids; `webhooks/format.ts` and `kinds.ts` add `note.deleted`; `npm run relay:api-doc`.
- Phone, in `mobile/lib/`: `data/store.dart` gets a hidden delete mark, a `note.delete` outbox item, and drops pulled deletes; `data/api.dart` and `data/webhook.dart` send it; `controller.dart` runs the *Undo* time; the note page's ⋯ menu in `screens/note_editor.dart` and the note rows in `screens/timeline.dart` get *Delete* and the swipe; `home.dart` and `folder.dart` stay as they are.
- Docs and site: the *Device keys* rule in `AGENTS.md`; `wiki/relay-spaces.md`; `site/src/content/docs/app/your-notes.md`, `connections/your-database.md`, the privacy page, `site/public/webhooks/receiver.mjs` and `v1.schema.json`.

## Decision log

- **2026-11-08** — Asked where Delete goes → chose the note page's ⋯ menu, and a swipe left on a note row, like Apple Notes (settled in the request).
- **2026-11-08** — Asked how far a delete goes → chose everywhere: the phone, the person's page, other phones, and a *note deleted* message to webhooks (settled in the request).
- **2026-11-08** — Assumed: a short *Undo* after delete, not an "Are you sure?" box, because Apple Notes deletes at once and a box slows every delete (settled in the request as assumed).
- **2026-11-08** — Assumed: the delete reaches the server only after the *Undo* time ends, because then *Undo* needs no restore on the server, and webhooks never get a delete that was taken back.
- **2026-11-08** — Assumed: a phone can delete any note in its space, also one from email, Claude Code or another phone, because a synced phone can already edit any note.
- **2026-11-08** — Assumed: a delete wins over an edit made on another phone, because an edit that reaches a deleted note has no note to change (`404`), and the note stays gone.
- **2026-11-08** — Assumed: an emptied note is deleted everywhere, because Apple Notes does this, and the old rule only kept the server copy because no delete existed.
- **2026-11-08** — Assumed: a delete made offline or with sending off waits on the phone and goes when sending is on again, because otherwise a later sign-in brings the note back.
- **2026-11-08** — Assumed: with *My own webhook*, the phone sends `note.deleted` to that webhook and does not call Relay Everything, as it does for edits.
- **2026-11-08** — Assumed: a full swipe left deletes, with a red bin behind the row, built from Flutter's own swipe (`Dismissible`) with no new package, because *Undo* makes a half-swipe button unnecessary.
- **2026-11-08** — Assumed: the server deletes the note's files and recording from storage at once, because a deleted note must not leave data behind.
- **2026-11-08** — Told by the daily line-up → this chat owns Delete everywhere, moved here from the *Phone app small UI improvements* plan. The build waits only for PR #64 to merge, and takes the ⋯ menu as it is on `main` then. It leaves `home.dart` and `folder.dart` to that chat, and keeps #65's plain tap on Home section names.
- **2026-11-08** — Told by the daily line-up → *Delete* goes in the shared ⋯ menu widget when *Phone app small UI improvements* has landed it by the build's start. Otherwise it goes in the old `_MoreMenu`, and the build report names the merge clash.
- **2026-11-08** — Assumed: `0012_note_deletes.sql` also rebuilds `relay_outbox` with the `note.deleted` kind, because its CHECK refused a new kind, as `0008_photos` found for `photo`.
- **2026-11-08** — Assumed: a deleted note's change row keeps the note's `client_id`, and `GET notes?deleted=1` gives `{ id, clientId, deleted: true }`, because a phone that sent the note before any pull has no server `id` to match.
- **2026-11-08** — Assumed: the phone queues `note.delete` also for a note whose first upload still waits, because that upload may be on its way; a `404` for one that never landed is dropped.
- **2026-11-08** — Assumed: a webhook backfill can send a `note.deleted` again, because the send log keeps it; a receiver deletes by `id`, so a repeat is harmless.
- **2026-11-08** — Assumed: `dropEmptyNote` answers `kept`, `dropped` or `deleting` (`Emptied`), because the note page shows *Undo* only for a note deleted everywhere.
- **2026-11-08** — Assumed: the swipe's bin icon uses the brand's `onDanger` color on `danger`, because the brand has that pair for text on red.
- **2026-11-08** — Assumed: a mark still inside its *Undo* time at app start gets a timer for the time left, and an older one is deleted at once, because the share card's window can start while the app's *Undo* runs.
- **2026-11-08** — Assumed: the route page shows an array of a union by its first object's fields (`api-doc.ts`), with a line for the deleted shape, because `GET notes` now gives two shapes and the page lost every note field.
- **2026-11-08** — Assumed: each note row in the list is its own screen-reader node (`Semantics(container: true)`), so its *Delete* action is on that row only.
- **2026-11-08** — Assumed: an emptied note whose first upload is waiting goes the way of a sent note (mark, *Undo*, queue note.delete), because its upload may already be on its way, and the server answers 404 to a delete for a note it never got.
- **2026-11-08** — Assumed: the delete runs when the *Note deleted* bar closes with no *Undo*, with a 10-second timer (`deleteAfter`) only for when no bar closes, such as after a close, because the bar's own five seconds start only after it slides in and it can wait behind a closing bar, so a fixed five-second timer could delete while *Undo* still shows.
- **2026-11-08** — Assumed: a pulled delete of a note this phone marked deleted holds the sync place, as the note open in the editor does, because after *Undo* the next pull must still delete it.
- **2026-11-08** — Assumed: #66 merged during the build, so *Delete* moved into its shared ⋯ menu (`more_menu.dart`) as a new optional `destructive` item, drawn last in the danger color; the old `_MoreMenu` is gone with #66, and no second menu was made.
