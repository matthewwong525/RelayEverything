# Design: sync notes across phones

## Context

See [proposal.md](proposal.md) for why. This change builds on `apple-notes-editing`, which must be on `main` first. That change adds `relay_notes.edited_at` (`0010_note_edits.sql`), `PATCH notes` for a phone key's own notes by `clientId` (`edit-note.ts`), `asPersonOrPhone` and the phone's `GET connections` reach in `caller.ts`, and `LocalNote.editedAt` with a `note.update` outbox item on the phone.

Today, as owned by [person spaces](../../../wiki/relay-spaces.md):

- `GET timeline` pages notes newest first, by `recorded_at`, for a session only. It can't say what changed since a phone last looked: an edit keeps the note's time, and a late ring or inbox note lands among older ones.
- A phone key reaches `POST` routes, `GET key` and `GET connections`. `GET attachment` and `GET audio` are `asPerson`, so they refuse a key.
- The phone's `notes` table is keyed by `client_id`, the phone's own id. Its outbox sends in order. Sending happens in `controller.dart` and in the hourly `backgroundRound`.

## Goals / Non-Goals

**Goals:** a change feed that can't miss or repeat a change; one note per server note on every phone; conflict resolution that doesn't depend on arrival order; no new reach beyond notes, their files and old ring recordings.

**Non-goals:** live push; a delete that spreads; merging two edits word by word; syncing anything but notes.

## Decisions

### A change log with a growing number, not a time cursor

`0011_note_sync.sql` adds:

```sql
CREATE TABLE relay_note_changes (seq INTEGER PRIMARY KEY AUTOINCREMENT, note_id TEXT NOT NULL UNIQUE REFERENCES relay_notes(id) ON DELETE CASCADE);
```

Triggers delete the note's row and insert it again after an insert on `relay_notes`, after an update of `text`, `lat`, `place`, `edited_at` or `audio_key`, and after an insert on `relay_attachments` or an update that makes its file ready. `AUTOINCREMENT` gives the new row a higher `seq`, so each note has one row, at its newest change. They delete and insert, not `INSERT OR REPLACE`, because an outer statement's conflict clause replaces a trigger's own. A step at the end fills one row per existing note, ordered by `recorded_at`.

`GET notes?since=<seq>&limit=<n>` returns `{ notes, next, more }`: the notes whose row has `seq > since`, in `seq` order, up to 100, and the last `seq` as `next`. A phone stores `next` and asks again while `more` is true.

*Why not `max(recorded_at, edited_at)`?* Two writes in one millisecond and phone clocks that differ both lose changes at a page edge. A number written inside the space's single writer can't.

### The note a phone gets

Each note: `id`, `clientId`, `mine` (its `device_id` is the caller's device), `source`, `text`, `recordedAt`, `editedAt`, `device` (the device's name), `place`, `audio` (a ring recording exists), and `attachments` (id, name, type, size, ready). It is the timeline note plus `clientId`, `mine` and `editedAt`. Build it from the same query helper `notePage` uses in `queries.ts`, so the two stay one shape.

The route uses `asPersonOrPhone`. `caller.ts` lets a `phone` reach `GET notes`, `GET attachment` and `GET audio`, and nothing else new. `attachments.ts` and `audio.ts` move from `asPerson` to `asPersonOrPhone`, still opening files only through the caller's space, so [the one-door rule](../../../wiki/relay-spaces.md#the-one-door-rule) holds.

### Changing any note, and the newer change wins

`PATCH notes` takes either `clientId` (this device's note, as today) or `id` (any note in the space), and a new `editedAt`, the time the phone made the change. When the stored `edited_at` is later than `editedAt`, the server changes nothing and answers `409`. New files go only on the phone's own note: `POST attachments` takes bytes only for a note the same device sent, so a new file on another device's note answers `400`. Otherwise it writes the words with `edited_at = editedAt`, logs `note.updated` as the editing change does, and the trigger moves the note's change row.

*Why the phone's time, not arrival order?* Arrival order lets a phone that was offline overwrite newer words. A phone clock can be wrong. The server clamps `editedAt` to its own now, so a clock set in the future can't lock a note.

The editing change drops a `PATCH` answered `404` or `400`. A `409` is dropped the same way, so the outbox never stalls. The answer holds no note, because the action contract passes on only an error's code and message; the pull that runs right after the outbox gets the newer words.

### The phone's store

A new store version adds to `notes`: `server_id TEXT UNIQUE`, `device TEXT`, `mine INTEGER NOT NULL DEFAULT 1`, `edit_unsent INTEGER NOT NULL DEFAULT 0`, and a nullable `path` in `attachments`, empty for a synced file until it is opened. `state` holds `note_sync_seq`.

A pulled note matches a local note by `server_id`, then by `client_id` against this phone's own notes, whatever `mine` says, so a phone's own note never shows twice. A new key is a new device on the server, which then calls the phone's older notes not its own. Phone ids are 32 random hex characters and email ids start `email:`, so no other note matches. A change goes by `id` once a pull saved one. A note from elsewhere gets `client_id = 'srv:' || id`, and is never sent by `POST notes`; changes to it go as `PATCH notes` with `id`.

Applying a pulled note: when the local note has a waiting `note.update` with a later `editedAt`, or nothing waits but it has an edit that never went with a later `edited_at` and other words, keep the local words; the second case queues a `note.update`. Else take the pulled words and drop any waiting update.

*Why a mark, not the edit time alone?* The server keeps `min(editedAt, now)`, so it keeps a fast phone's sent edit at an earlier time than the phone does. The time alone then reads a sent edit as unsent, and sends the old words again over a newer change from another phone. It also sends again a change the server dropped with `404`, `413` or `400`. So `edit_unsent` is set when `editNote` keeps a change and queues none, as with sending off, and is cleared when a change is queued or pulled words are taken.

### When the phone pulls

A new `data/note_sync.dart` pulls until `more` is false, then saves `next`. It runs only when sending is on and the destination is Relay Everything. It runs after the outbox has sent, so the phone's own changes are on the server before it reads. The triggers: app start and resume in `controller.dart`, pull-down on the notes list, and the end of `backgroundRound`. A `401` stops it, as the key check does today.

### Signing out

`KeyVault.forget()` callers also delete notes with `mine = 0`, their attachment rows and any downloaded files, and reset `note_sync_seq`. A later sign-in pulls from `0` again.

### Webhooks

No new webhook code: `POST notes` logs `note.created` and `PATCH notes` logs `note.updated`, whichever device calls. A test checks that a change by `id` from another device logs one `note.updated`, and that a refused `409` logs none.

## UX

### Use-case brief
A person with two phones, or a new phone, wants the same notes on each, as in Apple Notes. Done: open either phone and see every note, newest first. Common case: a note from the other phone or from email appears on open. Edge cases: an offline edit meets a newer one; signing out of a shared phone.

### Flow
Open the app → the list shows what is there at once → new notes come in a moment later. Pull down to fetch now. Tap a file to download and open it.

### Hierarchy
The list keeps its one primary action, *New note*. A note from elsewhere names its source in the muted time line under its title, never as a badge. A note from this phone shows no source, so the list stays quiet.

### Review
[review.html](review.html): What Changes items 1 and 3 sketch the list and the note page.

## Risks / Trade-offs

- [A lost phone reads every note until *Turn off*] → The privacy and keys pages say so, and say to turn off a lost phone at once.
- [A first sync of thousands of notes is slow] → Pages of 100; the list shows each page as it lands.
- [The hourly background round reads the key and server at its start] → A server change or sign-out in the app while that round runs can't stop its pull, so the old server's notes and pull place can land after the delete. The round lasts seconds, so this is rare; the app's own pull is awaited before the delete.
- [An edit in the editor while a pull changes the same note] → The pull skips the note open in the editor, and takes it at the next pull.
- [Two branches' space steps on staging] → As [the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order) says: deploy this branch's spaces Worker again before the staging check.

## Migration Plan

1. Wait for `apple-notes-editing` on `main`; bring `main` in.
2. Deploy the spaces Worker before the app, so `0011` runs as each space opens.
3. Old phones keep working: they never call `GET notes`. A new phone build pulls from `0` once.

Rollback: an older app build ignores the new columns. The `relay_note_changes` table can stay; no route reads it once the code is gone.
