# Tasks

## 1. Start from the editing change

- [ ] 1.1 Confirm `apple-notes-editing` is archived on `main`, then bring `main` into this branch. Verify: `edit-note.ts`, `schema/space-migrations/0010_note_edits.sql` and `asPersonOrPhone` exist here. If the editing change renamed a route or step, update design.md first.

## 2. The server

- [ ] 2.1 Write `schema/space-migrations/0011_note_sync.sql`: `relay_note_changes`, its triggers on `relay_notes` and `relay_attachments`, and one row per existing note in `recorded_at` order; register it in `spaces-worker.ts`. Test in `space-schema.test.ts`: an insert, a text change, a new file and a file made ready each move the note's row to a higher `seq`, and each note keeps one row.
- [ ] 2.2 Write `app/worker/apps/relay/note-sync.ts`: `GET notes?since=&limit=` with `asPersonOrPhone`, the note shape from design.md built with `notePage`'s helper, `next` and `more`; register it in `api.ts`. Tests: pages of changes in `seq` order with no repeat or gap across a page edge; `mine` is true only for the caller's device; Ana's key gets none of Ben's notes.
- [ ] 2.3 In `caller.ts`, let a `phone` key reach `GET notes`, `GET attachment` and `GET audio`; move `attachments.ts` and `audio.ts` to `asPersonOrPhone`. Tests in `device.test.ts`: a phone key reads notes and opens a file; a phone key is still refused on `GET timeline`, `GET summary`, `GET chats`, `GET photos` and the delete routes; a chat key and an API key are refused on `GET notes`.
- [ ] 2.4 In `edit-note.ts`, take `id` or `clientId`, and `editedAt`; clamp `editedAt` to now; answer `409` with the stored note when the stored `edited_at` is later. Tests: a phone changes an email note by `id` and one `note.updated` is logged; an older change gets `409` and logs nothing; a future `editedAt` is clamped.
- [ ] 2.5 Run `npm run relay:api-doc` in `app/`. Update `wiki/relay-spaces.md` for `0011` and the phone key's new reach, and the *Device keys* rule in `AGENTS.md` (a phone key reads its notes and changes any note in its space).

## 3. The phone

- [ ] 3.1 `mobile/lib/data/store.dart`: a new store version with `server_id`, `device`, `mine`, a nullable attachment `path`, and `note_sync_seq` in `state`; `applyPulled()` by the matching and newer-wins rules in design.md. Tests in `mobile/test/store_test.dart`: an own note pulled back stays one note; a note from elsewhere is added once; a waiting newer local change keeps its words; an older one is dropped.
- [ ] 3.2 Write `mobile/lib/data/note_sync.dart`: pull pages until `more` is false and save `next`; only with sending on and Relay Everything picked; after the outbox sends; skip the note open in the editor. `api.dart` gets `getNotes()`. Tests: no network call with sending off or own webhook; a `401` stops it; three pages land in order.
- [ ] 3.3 Edits of a note from elsewhere go as `PATCH notes` with `id` and `editedAt`; a `409` takes the stored note and leaves the outbox. Tests in `mobile/test/` for both.
- [ ] 3.4 Pull on start and resume in `controller.dart`, on pull-down in the notes list, and at the end of `backgroundRound` in `sync/background.dart`. Widget test: pull-down shows a new note from the fake server.
- [ ] 3.5 The list shows the source of a note from elsewhere in its time line; the note page names its source and lists files with no local copy; a tap downloads one with `GET attachment` (or `GET audio` for a ring recording) and opens it. Widget tests: one tap downloads one file; a phone's own voice note from elsewhere shows words and no *Play*.
- [ ] 3.6 Sign-out and *Forget* delete notes with `mine = 0`, their files and `note_sync_seq`. Settings, under *My own webhook*, says sync is off there and links to adding a webhook on the page. Tests for both.

## 4. The website

- [ ] 4.1 Update `site/src/content/docs/privacy.md` (a phone's key reads your notes and their files, not health, places, calendar or photos; turn off a lost phone), the keys page under `site/src/content/docs/api/`, `site/src/content/docs/app/your-notes.md` (notes on every phone, edit anywhere, newer wins, files on tap, sign-out) and the webhooks page (changes from any phone arrive as `note.updated`). Verify: `node scripts/product-name.test.mjs` passes.

## 5. Checks

- [ ] 5.1 `flutter analyze` and `flutter test` in `mobile/`; `npm test` in `app/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`.
- [ ] 5.2 `/save`, deploy this branch's spaces Worker to staging, then on staging with two phone keys: a note sent with key A shows in key B's `GET notes`; key B changes it by `id`; a test webhook gets one `note.updated`; an older change from key A gets `409`; key B is refused on health.
- [ ] 5.3 The iPhone device check: sign in, see a note sent by another key, open its file, sign out and see only this phone's notes.
