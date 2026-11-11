# A note keeps no place: its place goes into your location history

**Status:** ready-to-ship
**Branch:** spotty-emu
**Open questions:** none

## Why

Today a note can carry its own place, from a *Pin notes to where I am* switch. That keeps the same kind of data in two places: on the note and in your location history. You asked for one place: a note holds its words and its time, and your location history holds where you were. Your AI finds where a note was written by its time, as it already joins your health and your day by time.

## What Changes

- **Keeping a note adds one point to your location history.** When location history is on, the phone takes one fix as you keep a note, and adds it to your location history at the note's time, with its street name when the phone finds one. The point goes where your other points go: to Relay Everything, or only to your own webhook when you picked that. When location history is off, the phone reads no place for a note at all.
  ```mermaid
  flowchart TD
    K["You keep a note"] --> T["Note: words, time"]
    K --> Q{"Location on?"}
    Q -- yes --> P["Point at note's time"]
    Q -- no --> N["No place read"]
  ```

- **No switch for it.** *Pin notes to where I am* goes from Settings. Location history on means a point with each note; off means none.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Before</span>
      <h3>Settings</h3>
      <div class="row"><span class="grow">Signed in</span><span class="muted">you@example.com</span></div>
      <div class="row"><span class="grow">Appearance</span><span class="muted">System</span></div>
      <span class="muted">Notes</span>
      <div class="row"><span class="grow">Pin notes to where I am</span><span class="tag">On</span></div>
      <div class="row"><span class="grow">Voice notes</span><span class="muted">Speech model</span></div>
    </div>
    <div class="card col gap phone">
      <span class="muted">After</span>
      <h3>Settings</h3>
      <div class="row"><span class="grow">Signed in</span><span class="muted">you@example.com</span></div>
      <div class="row"><span class="grow">Appearance</span><span class="muted">System</span></div>
      <div class="row"><span class="grow">Voice notes</span><span class="muted">Speech model</span></div>
    </div>
  </div>
  ```
  No real picture: not tried, because the app has no build with sample notes for the browser, and this only takes away one row.

- **A note shows no place in the app.** On the phone and in the browser, a note shows its time and whether it was sent, with no street or *Pinned* under it. Search looks in a note's words and file names. Your places stay in location history and in your day.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Before</span>
      <div class="col"><b>Bought milk</b><span class="muted">9:41 · Queen St W · Sent</span></div>
      <div class="col"><b>Call Sam back</b><span class="muted">10:02 · Pinned · Sent</span></div>
    </div>
    <div class="card col gap phone">
      <span class="muted">After</span>
      <div class="col"><b>Bought milk</b><span class="muted">9:41 · Sent</span></div>
      <div class="col"><b>Call Sam back</b><span class="muted">10:02 · Sent</span></div>
    </div>
  </div>
  ```
  No real picture: not tried, for the same reason.

- **Your AI and your scripts find a note's place by its time.** A note in an answer has no place of its own. Your AI already gets the stays near a note's time when it reads one note, and it reads your day's places and points by time.
  | Who reads | Before | After |
  |---|---|---|
  | Your AI, one note | the note's place, and places nearby | places nearby by time |
  | Your AI, notes by search or time | each note's place | no place; it asks your places by time |
  | Your scripts, the web API | each note's place | no place; they read places by time |
  | A script that sends a note with a place | the place stays on the note | one point in location history at the note's time |

- **Your webhooks get a note with no place.** A note message carries no place, so a webhook that takes only notes never learns where you were. A webhook you ticked for location gets the note's point as one more location point.
  | Webhook ticked for | Before | After |
  |---|---|---|
  | Notes only | the note, with its place | the note, no place |
  | Notes and location | the note with its place, and points | the note, and points with the note's point |

- **Places already on your notes move into your location history.** Each note with a place gives one point at the note's time, and the note then keeps no place. Your webhooks are not sent these points again: they already got each one inside its note. On the phone, a note that waits to be sent gives its point when location history is on; any other place kept on a note on the phone goes. This can't be undone.
  | A made-up note | Before | After |
  |---|---|---|
  | *Bought milk*, 9:41 | on the note: Queen St W | in location history: a point at 9:41, Queen St W |
  | *Call Sam back*, 10:02, not sent, location off | on the note: Pinned | gone |

- **The website says so.** The pages on your notes, location, Settings, Shortcuts, your database and webhooks, and the API reference, say a note keeps no place and its point goes into location history.

Non-goals: no new setting; no place shown by time under a note, in the app or the browser; no change to how location history makes stays and trips; no change to what a phone key may read.

## What the build needs

- **Nothing.** No key or login; the move of old places runs by itself when the server is published.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-notes`: a note keeps no place; a place sent with a note becomes one location point; old note places move into location history.
- `relay-places-timeline`: keeping a note with location history on adds one point at the note's time.
- `relay-settings`: the phone's Settings has no *Notes* group and no *Pin notes to where I am* (builds on `settings-same-everywhere`).
- `relay-shortcuts`: *Add a note* adds a location point as a note made in the app does, and gives back no place.
- `relay-sending`: the offline scenario no longer pins notes.
- `relay-webhooks`: a note message has no place.
- `relay-note-sync`: a synced note comes with no place.
- `relay-notes-screen`: search reads words and file names only.

## Impact

- Phone: `mobile/lib/controller.dart` (`keepNote`, `keepRecording`, `_pinThenSync`, `setPinNotes`, `_entryOfLocal`), `lib/data/settings.dart` (`pinNotes`), `lib/data/store.dart` (`LocalNote.pin`, `pinning`, `settlePin`, a local migration), `lib/relay.dart`, `lib/web/web_relay.dart`, `lib/screens/settings.dart`, `timeline.dart`, `days.dart`, `note_editor.dart`, `lib/shortcuts/bridge.dart`, `ios/Runner/RelayIntents.swift`, `lib/data/api.dart` and the note-sync reader; `mobile/device-check/flows/settings.yaml`; tests in `mobile/test/`.
- Server: `schema/space-migrations/0017_note_places.sql` (copy places into `relay_locations`, with no webhook message, then empty `lat`, `lon`, `accuracy`, `place`, `place_from` on `relay_notes`); `app/worker/apps/relay/add-note.ts`, `notes.ts`, `queries.ts`, `timeline.ts`, `note-sync.ts`, `kinds.ts`, `webhooks/format.ts`; `app/worker/relay-mcp/openapi.ts`, `inputs.ts`; `npm run relay:api-doc`.
- Docs: `site/src/content/docs/app/your-notes.md`, `app/location.md`, `app/settings.md`, `app/shortcuts.md`, `app/share.md`, `connections/your-database.md`, `privacy.md`, `health-privacy.md`, the webhooks format page and `site/public/webhooks/receiver.mjs`; `mobile/README.md`.
- Builds after `settings-same-everywhere` ships.

## Decision log

- **2026-11-10** — Asked (in the planning chat) how a note's place should work → chose no place on the note: with location history on, keeping a note adds one point to location history at the note's time, with no setting; location off reads no place.
- **2026-11-10** — Asked (in the planning chat) what happens to places already on notes → chose to copy each into location history as one point at the note's time, then remove it from the note.
- **2026-11-10** — Asked what the app shows under a note → chose no place under a note, on the phone and in the browser, because a phone key may not read places.
- **2026-11-10** — Asked when to build, as *One simple Settings on the phone and the web* still shows the pin switch → chose to build after that change ships, on top of its new Settings.
- **2026-11-10** — Assumed: the note's point follows *What to send*, so with *Only stays and trips* it joins the open stay or trip and no raw point goes, because the person asked for one more location value, handled as every other.
- **2026-11-10** — Assumed: the point's time is the note's time, not the fix's, because the fix is taken as the note is kept (at most 10 seconds) and a lookup by time then finds it exactly.
- **2026-11-10** — Assumed: a note made earlier than now, such as from the share card or a shortcut with its own time, adds no point, as it pins no place today, because the phone's fix would be at another time.
- **2026-11-10** — Assumed: the server still takes `lat` and `lon` on a new note, from the web API, the connector's `add_note` and older phone builds, and keeps them as one location point at the note's time, because an older phone would otherwise have its notes refused and no place is lost.
- **2026-11-10** — Assumed: a webhook's note message drops `place`, because a note goes to every webhook and a place may go only to webhooks ticked for location (AGENTS.md); version 1 may still change before the public release.
- **2026-11-10** — Assumed: the moved points send no webhook message, because each webhook already got the place inside its note.
- **2026-11-10** — Assumed: a moved point with no accuracy gets 0, as the phone sends a point whose accuracy it does not know.
- **2026-11-10** — Assumed: `relay_notes` keeps its place columns, emptied and never read, not made again without them, because making the table again deletes every note's files through their link to it, and the table's place check stops a plain column drop.
- **2026-11-10** — Asked (at /ship) whether to build now, as *One simple Settings on the phone and the web* is not published yet → chose to wait, and build and publish this plan after that change is published.
- **2026-11-11** — Assumed (build): a note from the watch, the share card, or a shortcut that ran while the app was closed adds no point, as none pinned a place before, because it reaches the app after it was made and the fix would be at another time.
- **2026-11-11** — Assumed (review): a voice note recorded in the app takes its fix as the recording starts, at the note's time, and adds its point only when the note is kept, because a fix taken when a 5-minute recording stops would put the start time at a later place.
- **2026-11-11** — Built after *One simple Settings* went live (#105), on the newest main; the migration is `0017_note_places.sql`, as `0016_memory.sql` took 16. A second look found the API reference still said a note keeps its place, and an in-app voice note took its fix when the recording stopped; both fixed. Local checks pass; the live check (5.2) runs after this save.
- **2026-11-11** — Live check (5.2) passed on this computer: the move left a made-up note with no place and its file, added one point at its time with accuracy 0, and wrote no webhook message or note change; a note sent with a place through an API key showed no place in `GET /v1/notes`, and its point was in `GET /v1/points`. The key was turned off after.
- **2026-11-11** — Archived for publish: all tasks done, live check 5.2 passed.
