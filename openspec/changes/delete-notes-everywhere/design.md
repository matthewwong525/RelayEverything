# Design: delete a note everywhere

## Context

See [proposal.md](proposal.md) for why. This change builds on one unpublished change, which must be on `main` first:

- `sync-notes-across-phones` (PR #64): `relay_note_changes` with its triggers (`0011_note_sync.sql`), `GET notes?since=` (`note-sync.ts`, `noteChanges` in `queries.ts`), `PATCH notes` by `id` or `clientId` with `409` for an older change (`edit-note.ts`), and on the phone `server_id`, `mine`, `edit_unsent`, `applyPulled()` and `data/note_sync.dart`.
This change does not wait for *Phone app small UI improvements*, which edits `home.dart` and `folder.dart`. This change leaves those two files alone. It also keeps #65's plain tap on Home section names.

Today:

- The server has no note delete. `relay_note_changes.note_id` references `relay_notes(id) ON DELETE CASCADE`, so a deleted row would leave no trace a phone can pull.
- The webhook sender builds each message from the row as it is now; a row gone since answers `"skip"` (`kinds.ts`). So a waiting `note.created`, `note.updated` or `note.file` for a deleted note is never sent.
- The phone has `dropEmptyNote()` and `dropNote()`, which delete only an unsent or empty note on the phone, and remove its waiting `notes` and `note.update` items.

## Goals / Non-Goals

**Goals:** one delete that reaches the phone, the space, other phones and webhooks; *Undo* with no server restore; a delete that can't be lost offline or with sending off; no data left in storage.

**Non-goals:** a web page *Delete*; *Recently Deleted*; a `/v1/` or AI connector delete; restoring a note after the *Undo* time.

## Decisions

### A deleted note keeps a change row

`0012_note_deletes.sql` rebuilds `relay_note_changes` as `(seq INTEGER PRIMARY KEY AUTOINCREMENT, note_id TEXT NOT NULL UNIQUE, deleted INTEGER NOT NULL DEFAULT 0)`, with no foreign key. It drops the four triggers, copies the rows with their `seq`, renames the table, and makes the triggers again, plus one:

```sql
CREATE TRIGGER relay_note_changes_deleted AFTER DELETE ON relay_notes
BEGIN
  DELETE FROM relay_note_changes WHERE note_id = old.id;
  INSERT INTO relay_note_changes (note_id, deleted) VALUES (old.id, 1);
END;
```

The copy keeps `sqlite_sequence` at the highest `seq`, so the next number is still higher than every phone's last one.

`noteChanges` joins `relay_notes` with `LEFT JOIN` and, for a caller that asks with `deleted=1`, returns a deleted row as `{ id, deleted: true }`, in the same `seq` order; without it, deleted rows are skipped (see the migration plan). `GET notes` adds `deleted` to `syncedNote` as a second shape: a phone takes each change in order, so a note made and deleted between two syncs comes as one deleted id.

*Why not a `deleted_at` column on `relay_notes`?* Every read of notes (timeline, search, summary, `/v1/notes`, the AI connector, webhooks) would need a filter, and one missed read shows a deleted note. A real delete needs no filter. The rows left in `relay_note_changes` are an id and two numbers each.

### `DELETE notes`

A new `delete-note.ts`: `DELETE notes?id=` or `?clientId=`, for a phone key only (`asDevice`, `reaches === "phone"`), as `PATCH notes` finds the note. In one step:

1. Read the note's `audio_key` and its attachments' `file_key`s.
2. `space.files.remove(keys)`, files first, as `photoDelete` does, so a failed step leaves no row without its file.
3. `db.batch`: delete the note (attachments go by `ON DELETE CASCADE`; the trigger writes the change row) and insert `relay_outbox (kind 'note.deleted', ref id, at recorded_at, logged_at now)`.
4. `wake(env, space, ["notes"])`.

A note not there answers `404 not_found`, which the phone takes as done. `caller.ts` lets a `phone` reach `DELETE` on `/apps/relay/api/notes`, and nothing else new.

### `note.deleted`

`webhooks/format.ts` adds `envelope("note.deleted", { note: { id, deleted_at } })`; `kinds.ts` adds `note.deleted` to the notes kind's `log` and `messages`, built from the outbox entry alone (`ref`, `logged_at`), since the row is gone. `site/public/webhooks/v1.schema.json` is written again from `format.ts`, and the example `receiver.mjs` deletes the note and its files. *Send past data* replays only rows that exist, so it never sends a delete.

The phone's own webhook (`data/webhook.dart`) maps a `note.delete` item to `note.deleted` with the note's `clientId` as `id`, as `note.created` names it there.

### The phone: a hidden mark, then the delete

A new store version adds `deleting_at INTEGER` to `notes`. Every list and count reads `WHERE deleting_at IS NULL`.

- `Store.markDeleted(clientId, at)` sets `deleting_at`. `Store.undoDelete(clientId)` clears it.
- `Store.deleteNote(clientId)`, once the *Undo* time ends: in one transaction, remove the note's waiting `notes`, `note.update` and `attachment` items; when the note has a `server_id` or a `sent_at`, enqueue `note.delete` with `{ clientId, id: server_id }` (`id` when known, as `_changeOf` does); delete the note and its attachment rows, and its local files after the commit. A note never sent queues nothing.
- `note.delete` is queued also with sending off, unlike an edit. The outbox keeps it: `stopSending()` drops only readings and photos, nothing flushes while sending is off, and `moveOutbox()` carries it to the place picked when sending turns on. The outbox sends before the pull, so the delete reaches the space before the note could come back.
- `applyPulled()` deletes a local note for a `{ id, deleted: true }` change, with any waiting change of it. It skips the note open in the editor, as it does for a change, and a note with `deleting_at` set, whose own delete goes first.
- A `404` to `PATCH notes` drops the change, as today; the next pull then brings the delete.

`controller.dart` adds `deleteNote(id)`: mark, refresh, show *Undo*, and when its bar closes with no *Undo* (`endUndo`) run `store.deleteNote` and `sync()`; a 10-second `deleteAfter` timer runs it when no bar closes. `undoDelete(id)` stops the timer and clears the mark. At start, `controller.dart` finishes every note marked longer than `deleteAfter` ago, so a close during the *Undo* time still deletes.

`dropEmptyNote()` becomes the same path for a sent note, and for one whose first upload waits: an emptied note gets the mark and *Undo*; an emptied note never sent and never queued is dropped at once with no *Undo*, as today, since there is nothing to take back.

### Where Delete shows

- The note page's ⋯ menu gets *Delete* last. Look at `main` first. When *Phone app small UI improvements* has landed its shared ⋯ menu widget, add *Delete* to that widget, and make no second menu and no edit to the old `_MoreMenu`. When it has not landed, add *Delete* to `_MoreMenu` in `note_editor.dart`, copy none of that chat's work, and say in the build report that the two may clash at merge. The item is in the danger color with `CupertinoIcons.trash`. The note page calls `relay.deleteNote(id)`, pops, and the list shows the *Undo* snack bar.
- Each note row (`_NoteRow` in `timeline.dart`) sits in a `Dismissible` with `DismissDirection.endToStart`, a red background with a white `CupertinoIcons.trash`, and `onDismissed` calling `deleteNote`. Every notes list shows this row, so the swipe works there with no edit to `folder.dart`.
- One `showDeleted(context, relay, id)` shows `SnackBar('Note deleted', action: Undo)` for five seconds, from both places.

## UX

### Use-case brief
A person wants a note gone: a mistake, a done task, a private note. Done: the note is gone from every place with one action. Common case: swipe a note away in the list. Edge cases: delete by mistake (Undo), delete offline, delete with the person's own webhook. Mirrors Apple Notes' list swipe and its note ⋯ menu.

### Flow
List → swipe left → the row slides away → *Note deleted · Undo* for five seconds. Or note page → ⋯ → *Delete* → back on the list with the same *Undo*.

### Hierarchy
The list keeps its one primary action, *New note*. *Delete* is the last item of ⋯, in the danger color, never a button on the page. *Undo* is the snack bar's only action.

### Review
[review.html](review.html): What Changes items 1 and 2 sketch the ⋯ menu and the swipe with *Undo*.

### Components
The note page's ⋯ menu; Flutter's `Dismissible` and `SnackBar`. Nothing new.

## Risks / Trade-offs

- [A delete by mistake after the *Undo* time can't be taken back] → The proposal says so; *Recently Deleted* is a later plan if it is needed.
- [A phone that never syncs again keeps the note] → Only until its next sync; sign-out removes notes from elsewhere already.
- [The rebuild of `relay_note_changes` on a large space] → One copy of id rows per space, inside the space's migration step, once.
- [Two branches' space steps on staging] → Deploy this branch's spaces Worker again before the staging check, as [the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order) says.

## Migration Plan

1. Wait for both changes on `main`; bring `main` in.
2. Deploy the spaces Worker before the app, so `0012` runs as each space opens.
3. Old phones never send `DELETE notes`. The published sync build reads `recordedAt as int` from every pulled note, so a deleted id would stop its pull: `GET notes` returns deleted ids only to a caller that asks with `deleted=1`, which the new app sends. The new store version sets `note_sync_seq` to `0` once, so an updated phone pulls again from the start and gets every delete it skipped.

Rollback: an older server ignores `deleted`; the rebuilt table still serves `GET notes`.
