# Tasks

## 1. Server

- [x] 1.1 Add the space migration: `relay_notes.deleted_at`, its index, the change-row trigger on `deleted_at`, and the `note.recovered` outbox kind. Verify: `space-schema.test.ts` gets a migrate test that keeps existing notes and files, and a trigger test that a move and a recover each add a change row.
- [x] 1.2 Make `DELETE notes` move the note, with `forever: true` for today's hard delete, and add `POST notes/recover`; `PATCH notes` on a moved note answers 409 `deleted`. Verify: tests for move, recover, forever, 404 after forever, 409 on edit, another space's note refused.
- [x] 1.3 Add `deletedAt` to the `GET notes` feed, and `deleted_at IS NULL` to every other reader (`queries.ts`, `answers.ts`, `kinds.ts`, `audio.ts` for non-phone callers, `relay-memory/store.ts`). Verify: tests that a moved note is in the feed with `deletedAt` and absent from MCP `search`, `timeline`, day summary and memory.
- [x] 1.4 Purge after 30 days in the space alarm, and in `GET notes` as a backup, through the forever path. Verify: a test with a fake clock removes the note, files and recording at 30 days, not before, and sets the next alarm.
- [x] 1.5 Send `note.deleted` at a move and `note.recovered` at a recover (`kinds.ts`, `webhooks/format.ts`); run `npm run relay:api-doc` in `app/`. Verify: format tests, and the rewritten `site/` API reference and `v1.schema.json`.

## 2. App data (phone, Mac, web)

- [x] 2.1 Store: `notes.deleted_at`, mark migration from `deleting_at`, `deleted` list, move, recover, forever, local 30-day purge, outbox `note.recover` and `forever`; feed `deletedAt` applied at sync. Verify: `store_test.dart` and `note_sync_test.dart` cases for each, with sending off and on.
- [x] 2.2 `Relay` API in `RelayController` and `WebRelay`: `deleteNote` moves; `recover`, `recoverAll`, `deleteForever`, `deleteAll`, `undoLastDelete`, `canUndoDelete`; remove the undo timers; emptied sent note goes forever; own-webhook phones send `note.deleted` and `note.recovered`. Verify: `controller_test.dart`, `web_relay_test.dart`, `webhook_test.dart`.

## 3. App screens

- [x] 3.1 `showProblem` alert; replace every `showSnackBar` and the `notices` listeners; *Copied.* and *Secret copied.* show nothing; a test fails if `SnackBar` is in `mobile/lib`. Verify: `screens_test.dart` updates its *Note deleted* and *Copied* expectations; a test for the browser alert.
- [x] 3.2 *Recently Deleted* page, swipe *Recover* and *Delete*, ⋯ *Recover All* and *Delete All* with their confirm, read-only open with the recover alert; Home row and the wide shell's left bar row while not empty. Verify: `screens_test.dart` and `web_shell_test.dart` cases, and `mac_shell_test.dart` for the left bar.
- [x] 3.3 iPhone shake: `motionEnded` in the iOS runner calls `relay/shake`; Dart shows *Undo Delete Note* when `canUndoDelete` and no text has focus. Mac menu *Undo* and web ⌘Z / Ctrl+Z call `undoLastDelete` when no text has focus. Verify: widget tests that send the channel call and the key, and a Maestro flow `mobile/device-check/flows/recently-deleted.yaml` for swipe → *Recently Deleted* → *Recover*.

## 4. Docs

- [x] 4.1 Rewrite *Delete a note* in `site/src/content/docs/app/your-notes.md` (Recently Deleted, recover, shake, ⌘Z), and the `note.recovered` webhook in the webhook docs. Verify: the site builds and `scripts/product-name.test.mjs` passes.
- [x] 4.2 `wiki/brand.md`: add *No toasts; a problem is an alert* to *Rules for every screen*. Verify: the wiki link check passes.

## 5. Checks

- [x] 5.1 Redraw the plan's pictures from the built code with the plan's screen test and compare.
- [x] 5.2 `npm test` and `npm run lint` in `app/`, `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs`; then `/save` for CI and the preview, and the device check at `/verify`.
