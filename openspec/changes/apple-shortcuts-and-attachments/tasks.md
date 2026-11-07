# Tasks

## 1. Files in the space (server)

- [x] 1.1 Add `schema/space-migrations/0003_attachments.sql` with `relay_attachments`; extend `space-schema.test.ts` so a new space and an old one both have the table after migrations.
- [x] 1.2 Let `notes.ts` take an optional `attachments` list (at most 10, each `{id, name, type, size ≤ 25 MB}`) and insert one row per file in the same call; tests: a note with files, a resend stores one set, an eleventh file is refused with 400.
- [x] 1.3 Add `attachments.ts`: `POST attachments` (phone key, raw body, seals through `space.files` at `people/<person>/attachments/<id>`, once per id, 404 for an unlisted file, 413 over 25 MB) and `GET attachment?id=` (signed-in person, right `Content-Type` and `Content-Disposition`); route tests, and `isolation.test.ts` shows Ben's session can't open Ana's file; `space-access.test.ts` passes unchanged.
- [x] 1.4 Return each note's files with `ready` from `queries.ts` and `timeline.ts`; tests for a waiting and an arrived file.
- [x] 1.5 Add the optional `attachments` list to `note.created` in `webhooks/format.ts` and `send.ts`, present only for a note with files; regenerate `site/public/webhooks/v1.schema.json`; `format.test.ts` covers both shapes and that no bytes go.
- [x] 1.6 Run `npm run relay:api-doc` in `app/` and check `site/src/content/docs/api/reference.md` lists both routes; `account.test.ts` shows delete removes a file's object.

## 2. Files on the page

- [x] 2.1 Show a note's files in `app/src/apps/relay/Notes.tsx`: pictures inline through `GET attachment`, other files as a download link with name and size, a waiting file as *Waiting for the file*; component tests for the three states.

## 3. Files on the phone

- [x] 3.1 Store schema 5 in `mobile/lib/data/store.dart`: the `attachments` table, files copied into `attachments/<id>`, the note body's `attachments` list, one `attachment` outbox row per file after its note; migration test from schema 4 keeps every note.
- [x] 3.2 Add `RelayApi.upload` and send `attachment` rows in `outbox.dart` in order; a file that the server refuses is dropped, the note stays sent; tests with a fake server for order, resend and refusal.
- [x] 3.3 Add the 10-file and 25 MB limits and `addNote(text, files)` to `RelayController`, *Send them* queues earlier files; tests: a files-only note, a file too big, sending off makes no request.
- [x] 3.4 Add the paperclip to `screens/compose.dart` (`file_picker`) with removable chips, and files in `screens/timeline.dart` (thumbnails, file rows, open with `open_filex`); widget tests for the compose chips and the timeline rows.

## 4. Shortcuts actions (iPhone)

- [x] 4.1 Add `lib/shortcuts/` with `shortcutsMain` and the `relay/shortcuts` channel (`add`, `get`), and drain `shortcuts-inbox/` in `RelayController.load`; Dart tests for `add` (text, files, empty refused), `get` (count, words, since) and the inbox drain.
- [x] 4.2 Add `ios/Runner/RelayIntents.swift`: `AddNoteIntent`, `GetNotesIntent`, `StartVoiceNoteIntent`, `RelayNoteEntity`, `RelayShortcuts` provider, the warm `ShortcutsEngine`, the 20-second inbox fallback, all `@available(iOS 16, *)`; wire `AppDelegate.swift`; answer the design's open question; `flutter build ios --simulator` passes on the Mac check with deployment target 15.0.
- [x] 4.3 Add the tap-to-stop recording sheet that *Start a voice note* opens, reusing `startVoiceNote`/`endVoiceNote`/`cancelVoiceNote`; widget test for Stop and Cancel.
- [ ] 4.4 Add a device-check flow in `mobile/device-check/flows/` that runs *Add a note* on the simulator (`xcrun simctl` or a Shortcuts URL) and sees the note in the timeline.

## 5. Website and wiki

- [x] 5.1 Write `site/src/content/docs/app/shortcuts.md` (the three actions, the five recipes with steps, iOS 16, sending rules) and link it from the docs sidebar; add it to `scripts/product-name.test.mjs`.
- [x] 5.2 Update `site/src/content/docs/app/your-notes.md` (files, limits), `privacy.md` (files sealed in your space, sent only while sending), `connections/your-database.md` (`attachments`, optional fields may appear within a version); `mobile/README.md` names the Shortcuts bridge.

## 6. Checks

- [x] 6.1 Run `npm test`, `flutter test` in `mobile/`, `node scripts/public-check.mjs`, and `node scripts/product-name.test.mjs`; all pass.
- [x] 6.2 `/save`, then on staging: send a note with a picture and a PDF from the simulator build, see both on the page, download the PDF, and see `attachments` in a test webhook's `note.created`.
- [x] 6.3 Preview the website with `node scripts/publish-relay-site.mjs --ref HEAD --staging` and check the Shortcuts page.

After the publish (not tracked, because the TestFlight build comes only from `main`): Matthew makes a screenshot shortcut on his iPhone and sees the note with its picture in the app and on his page.
