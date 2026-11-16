# Design

## Context

See proposal.md for why. Today:

- **Server.** `DELETE notes` (`app/worker/apps/relay/delete-note.ts`) removes the R2 files, writes a `note.deleted` outbox row and deletes the `relay_notes` row at once. The trigger `relay_note_changes_deleted` (`0012_note_deletes.sql`) turns its change row into a tombstone, which `GET notes?deleted=1` sends to devices. `relay_notes` has no soft-delete column. Nothing purges on a schedule: the space alarm (`spaces-worker.ts`, 15 min) runs only while the space has a webhook. Readers of notes: `queries.ts` (`notePage`, `noteById`, `daySummary`, `noteChanges`), `answers.ts` (MCP `search`, `timeline`), `kinds.ts`, `audio.ts`, `relay-memory/store.ts`.
- **App.** `deleteNote` hides the note, marks `deleting_at`, and `_finishDelete` drops it after the 5 s bar (`undoTime`) or `deleteAfter`; `store.deleteNote` queues `note.delete`. The same `Relay` API runs in `RelayController` (phone, Mac) and `WebRelay` (web). About 25 `showSnackBar` calls show problems, *Copied.*, and the undo bar.

## Goals / Non-Goals

**Goals:** one soft-delete state shared by server and devices; every note reader leaves deleted notes out; old app builds keep working; no `SnackBar` left in `mobile/lib`.

**Non-Goals:** multi-select edit mode; three-finger undo; undo for anything but a delete.

## Decisions

### Server

- **Soft delete in `relay_notes`.** A new space migration adds `deleted_at INTEGER` and an index, and a trigger that writes a change row when `deleted_at` changes, so the feed carries moves in both ways. Never edit a ran migration; `relay_notes` is not rebuilt (a rebuild cascade-deletes files: `wiki/relay-space-migrations.md`).
- **`DELETE notes` moves by default.** It sets `deleted_at` and queues `note.deleted`. `forever: true` runs today's hard delete (files, row, tombstone). An old phone build that sends `DELETE` now moves the note: the safe way. Alternative: a new `POST notes/trash` route and keep `DELETE` hard. Rejected: old builds would still hard-delete.
- **`POST notes/recover`** with `id` or `clientId`: clears `deleted_at`, queues `note.recovered` (new outbox kind; if the `relay_outbox.kind` column has a CHECK list, the migration rebuilds `relay_outbox`, never `relay_notes`). 404 for a note deleted for good. Phone keys and the page only, as `DELETE`.
- **`PATCH notes` on a moved note** answers 409 with `deleted: true`; the device keeps it in *Recently Deleted*.
- **Feed.** `GET notes` rows carry `deletedAt` (null or ms). Hard deletes stay tombstones.
- **Readers.** Each reader above adds `deleted_at IS NULL`, except the phone-key reads of one note's files and recording, so a deleted note still opens to read.
- **Purge.** The space alarm also runs while a moved note waits: after each move it sets the alarm to the earlier of its webhook sweep and `min(deleted_at) + 30 days`. The alarm hard-deletes each note past 30 days through the same function as `forever`. As a backup, `GET notes` purges any note past due before it answers.
- **Docs.** `npm run relay:api-doc` rewrites the API reference, OpenAPI and webhook schema with `forever`, `notes/recover`, `deletedAt` and `note.recovered`.

### App (phone, Mac, web)

- **Store.** A local migration adds `notes.deleted_at`; any `deleting_at` mark becomes `deleted_at` (a note mid-undo on update lands in *Recently Deleted*, never lost). `entries` leaves deleted notes out; a new `deleted` list holds them, newest delete first.
- **`Relay` API.** `deleteNote` moves (no timer); new `recover(id)`, `recoverAll()`, `deleteForever(id)`, `deleteAll()`, and `undoLastDelete()` with `canUndoDelete`. `undoTime`, `deleteAfter`, `endUndo`, `undoDelete` and `showDeleted` go. The outbox gets `note.recover`; `note.delete` gains `forever`. With the person's own webhook, the phone sends `note.deleted` and `note.recovered` there itself.
- **Local purge.** At start and once a day while open, the device hard-deletes local notes past 30 days, also with sending off; signed-in devices also get the server's tombstones.
- **Emptied note.** `dropEmptyNote` hard-deletes (`forever`) a sent note it can't drop locally, instead of today's delete with *Undo*.
- **Recently Deleted page** (`screens/recently_deleted.dart`): `TitleBar` + `BackTo('Home')`, a muted 30-days line, `noteSliver` with a `deleted` mode (swipe actions *Recover* and *Delete*), ⋯ with *Recover All* and *Delete All*. Opening a note uses `NoteEditor` read-only; a tap in the words shows the recover alert. Home's first card and the wide shell's left bar add the row only while `deleted` is not empty.
- **Shake on iPhone.** `SceneDelegate`'s root `FlutterViewController` subclass overrides `motionEnded(.motionShake)` and calls `relay/shake`. Dart shows *Undo Delete Note* only when `canUndoDelete` and no text field has focus, so Flutter's own shake undo of typing in a note is untouched. The undo stack is this run only, as in UIKit.
- **⌘Z on Mac and web.** The Mac menu's *Undo* and a web `Shortcuts` binding call `undoLastDelete()` when no editable text has focus; else they undo typing, as today.
- **Alerts.** `showProblem(context, message)` in `screens/folder.dart` shows a `CupertinoAlertDialog`: the first sentence is the title without its stop, the rest the content, and *OK*. Every problem call site and the `notices` stream use it; *Copied.* and *Secret copied.* show nothing. A test fails if `SnackBar` appears in `mobile/lib`.
  - Alternative: a Material `AlertDialog` on Android. Rejected: the app already uses Apple's look on every platform.

## Risks / Trade-offs

- [Old app builds still show their 5 s bar, and their delete now moves the note] → safe: nothing is lost; the note waits in *Recently Deleted* once they update.
- [Flutter's own shake undo while typing and ours both fire] → ours runs only with no focused text field.
- [The alarm misses a purge while the space sleeps] → Durable Object alarms wake the space; `GET notes` purges as a backup.
- [Webhook receivers that delete their copy at `note.deleted` must handle `note.recovered`] → documented in the webhook docs; a receiver that ignores it keeps working, and the note is just missing there.

## Migration Plan

Publish the server first (`publish-relay-server.mjs`): soft delete is safe for old builds. Then the app build. Rollback: the server migration only adds a column and triggers; an older worker ignores `deleted_at`, so moved notes would show again until re-deleted, and nothing is lost.

## UX

### Use-case brief

The person deletes notes often, by swipe, sometimes by mistake, on a phone first. Done means the note is out of the list at once and can come back for 30 days. Edge: a delete on one phone and a recover on another; a note deleted while offline. Mirror Apple Notes on iOS 26: its *Recently Deleted* folder, recover alert and shake alert.

### Flow

Swipe → gone from the list (no message) → shake → *Undo* → back. Or: Home → *Recently Deleted* → swipe → *Recover* → back in *Notes*.

### Hierarchy

*Recently Deleted* has no *New note* and no accent button: its one action is *Recover*, in the swipe and in the alert. *Delete* and *Delete All* are red.

### Review

[review.html](review.html): *No more toasts* shows Before and the list after a swipe; *A problem shows as an alert*, *Recently Deleted*, *Recover or delete for good* and *Shake to undo* each show their screen.

### Components

`TitleBar`, `BackTo`, `FolderRow`, `noteSliver`, the swipe actions of the notes list, `NoteEditor` read-only, Flutter's `CupertinoAlertDialog`. New: the *Recently Deleted* page, and `showProblem`.
