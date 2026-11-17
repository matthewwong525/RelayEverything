# Tasks

## 1. Server: remove files from a note

- [x] 1.1 `PATCH notes` (`app/worker/apps/relay/edit-note.ts`): take `removed`, up to 10 file ids, only for a note the calling device sent; delete those `relay_attachments` rows and their sealed files (share the delete with `recently-deleted.ts`), skip an id the note lacks, and log one `note.updated`. A change with only `removed` counts as a change.
- [x] 1.2 Tests in `edit-note.test.ts`: a removal deletes the row and the sealed file and logs `note.updated`; another device's removal gets `not_own`; a resent removal changes nothing; a short `attachments` list with no `removed` deletes nothing; the webhook message lists only the files left.
- [x] 1.3 Run `npm run relay:api-doc` in `app/`.

## 2. Phone app: files in the words

- [x] 2.1 `mobile/lib/editor/markdown.dart`: read a line `![<name>](attachment:<id>)` as the block embed `{attachment: <id>}` and write it back byte for byte; `plainText` leaves it out. Tests: round trip, a line between words, a line with an unknown id, `plainText`.
- [x] 2.2 New `mobile/lib/editor/attachments.dart`: `AttachmentEmbedBuilder` draws `NotePicture`, `NoteFileRow` or `RecordingCard` by id, and keeps the card's taps and transcript field from the editor's own.
- [x] 2.3 `note_editor.dart` `_page`: only the date and one `QuillEditor`; on load, place each file with no line where it shows today (a `top` recording first, the rest at the end by `filesBefore`), and don't count that as a change.
- [x] 2.4 *Attach* and a dropped file: make each file's id (`NewFile.id`), insert its block at the cursor's line or at the end with no focus, then save. *Record*: remember the line, pass the new id to `startVoiceNote(into:, id:)`, insert the block on save, nothing on the X.
- [x] 2.5 Removal: on save, send the ids gone from the Delta as `removed`; block delete on a note from another device. `controller.dart` and `data/store.dart`: delete the row and any queued upload, keep the bytes until the page closes, add the file again from the kept bytes when Undo brings its id back; delete kept bytes on close. `web/web_relay.dart`: send `removed` for the web page and the Mac app.
- [x] 2.6 Pull (`store.dart`): delete local rows a pulled note no longer lists, and their bytes, except a file of this device's note still waiting to send.
- [x] 2.7 Widget and store tests: words after a photo keep their order after a reload; an older voice note shows its recording first and keeps it after typing; *Attach* at the cursor; delete then Undo; a note from another device keeps its files; a pull drops a removed file.
- [x] 2.8 Maestro flow `mobile/device-check/flows/media-between-words.yaml`: add a photo, type under it, close and open the note, and see the words under the photo.

## 3. Docs

- [x] 3.1 Website: `site/src/content/docs/app/your-notes.md` says files sit in the words, go at the cursor, and delete removes them; `site/src/content/docs/api/files.md` and the webhook page name the `attachment:` line and `removed`.
- [x] 3.2 `wiki/relay-spaces.md` *Recordings, note files and photos*: a phone key can remove a file of its own note.

## 4. Checks

- [x] 4.1 Run the Flutter tests in `mobile/` and `npm test` in `app/`; fix what fails.
- [ ] 4.2 `/save`, then `/verify` with the device check and the new flow.
