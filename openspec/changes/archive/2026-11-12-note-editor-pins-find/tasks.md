# Tasks

## 1. The server (`schema/space-migrations/`, `app/worker/apps/relay/`)

- [x] 1.1 Add `schema/space-migrations/0018_note_pins.sql`: `relay_notes.pinned_at` and `pin_changed_at`, and the `relay_note_changes_pinned` trigger; extend `space-schema.test.ts` to check that a pin change moves the note's change row and logs no `relay_outbox` row, and verify it passes.
- [x] 1.2 Add the `PUT notes/pin` action (`relay.notes-pin`, `asDeviceOrPage`) by `id` or `clientId`, with `at` clamped to now and 409 for an older change; register it in `api.ts`; add `notes-pin.test.ts` for pin, unpin, an older change, a phone's own note by `clientId`, and a refused key, and verify it passes.
- [x] 1.3 Give `pinned` and `pinChangedAt` in `GET notes` (`queries.ts`, `note-sync.ts`); extend `note-sync.test.ts`, run `npm run relay:api-doc` in `app/`, and verify the app tests pass.

## 2. The phone's data (`mobile/lib/data/`, `controller.dart`, `relay.dart`, `web/web_relay.dart`)

- [x] 2.1 Add schema step 14 with `notes.pinned_at` and `pin_changed_at`, `Entry.pinned`, and `Relay.pinNote`; enqueue `note.pin` only while sending to Relay Everything, replacing a waiting one for the same note and after the note's own upload; send it in `api.dart` and never to a webhook; add `store_test.dart` and `controller_test.dart` tests, and verify they pass.
- [x] 2.2 Apply the server's pin in the note pull when its `pinChangedAt` is newer and no `note.pin` waits for the note; add `note_sync_test.dart` tests for both cases, and verify they pass.
- [x] 2.3 Add the `pinnedFolded` setting, kept with the other settings, and `WebRelay.pinNote` through `PUT notes/pin`; add tests to `data_test.dart` and `web_relay_test.dart`, and verify they pass.

## 3. The note page (`mobile/lib/screens/note_editor.dart`, `note_bars.dart`)

- [x] 3.1 Set the tool bar's gap to 6 points while editing and keep the caret above it with the design's post-frame scroll to the caret (not `scrollBottomInset`, which hides a caret that moves up); add a `screens_test.dart` test that the caret's rect ends above the tool bar after typing at the end of a long note, and verify it passes.
- [x] 3.2 Add *Undo* and *Redo* to the top bar from the controller's history, with the keyboard kept up; add `screens_test.dart` tests for no Undo before a change, Undo then Redo, Redo gone after a new change, and an undone change kept, and verify they pass.
- [x] 3.3 Add *Pin Note* / *Unpin Note* and, on a phone only, *Find in Note* to the ⋯ menu, and the `FindBar` find mode as the design says; add `screens_test.dart` tests for the menu items, *1 of 3* stepping round with capitals ignored, *No matches*, ✓ closing it, and no change to the note's words, and verify they pass.

## 4. The notes list (`mobile/lib/screens/timeline.dart`)

- [x] 4.1 Show the *Pinned* part first, with its fold and no tap shade, and leave pinned notes out of their day groups, after the filter and search; add `screens_test.dart` tests for the part, the fold kept after a restart, and search with no pinned match, and verify they pass.
- [x] 4.2 Add the swipe right that pins or unpins and the screen reader's *Pin* / *Unpin* action; add a `screens_test.dart` test, and verify it passes.
- [x] 4.3 Write a Maestro flow in `mobile/device-check/flows/` that pins a note from its ⋯ menu, sees it under *Pinned*, folds *Pinned*, and types into a long note.

## 5. The guide and the wiki

- [x] 5.1 Update `site/src/content/docs/app/your-notes.md` with pin, the fold, the swipe, Undo and Find in Note, and the API page with `PUT notes/pin`; verify `node scripts/product-name.test.mjs` passes.
- [x] 5.2 Add `0018_note_pins.sql` to `wiki/relay-space-migrations.md`, and to the phone app wiki how the page keeps the caret above a floating bar; verify the wiki check passes.

## 6. Checks

- [x] 6.1 Run `flutter analyze` and `flutter test` in `mobile/`, and the app's type check and tests in `app/`, and verify all pass.
- [x] 6.2 `/save`, then run the device check on the saved commit with the change's flow and scenarios, and show its pictures. (The `note-pins` step passed in three checks; the fixed Settings step failed on a slow Mac, so Claude's part never ran; published by the person's choice.)
