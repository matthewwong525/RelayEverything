# Tasks

## 1. The editor and its Markdown codec (phone)

- [x] 1.1 Add `flutter_quill`, `markdown` and `share_plus` to `mobile/pubspec.yaml`; confirm `flutter build apk --debug` and `flutter build ios --no-codesign` pass on Flutter 3.47.9. If `flutter_quill` fails, switch to `appflowy_editor` and note it in design.md.
- [x] 1.2 Write `mobile/lib/editor/markdown.dart`: Markdown ↔ Delta for every style in design.md (Title/Heading/Subheading, Mono fence, bulleted `*`, dashed `-`, numbered, checklist `- [ ]`/`- [x]`, quote, indent, `**`, `_`, `~~`, `<u>`), plus `plainPreview()` for the list. Test in `mobile/test/markdown_test.dart`: each style round-trips byte for byte, and a corpus of plain old notes with stray `*`, `#` and `-` comes back unchanged.
- [x] 1.3 Use `plainPreview()` for the list's first line, rest and search in `timeline.dart`; test that a note starting `# Shop` and `- [ ] Eggs` lists as *Shop* and *Eggs*.

## 2. The note page (phone)

- [x] 2.1 Build `mobile/lib/screens/note_editor.dart` from `compose.dart` and `note.dart`: new notes open with the keyboard up and a Title first line; old notes open reading; files, pictures and *Play* keep their blocks; a voice note writing its words is read-only until they arrive. Delete `compose.dart` and `note.dart` and point the list, *New note* and the share flow at it.
- [x] 2.2 Save on a 1.5 s pause and on leave; never store an empty new note; never write back an unchanged note. Widget tests: fix a word and leave → list shows it; empty new note → nothing added; open and leave an old note → text and outbox unchanged.
- [x] 2.3 Build `RoundIconButton`, the top bar (back, share/⋯ pill, accent ✓ while editing), `FloatingToolBar` above the keyboard (Aa, checklist, paperclip) and `ReadingBar` (checklist, paperclip, compose). Every button has a tooltip and semantics label. Widget tests: ✓ closes the keyboard and shows the reading bar; compose opens a new note.
- [x] 2.4 Build `FormatSheet` in place of the keyboard: Title, Heading, Subheading, Body, Monostyled; B/I/U/S; three list kinds; quote; indent in and out; ✕ returns the keyboard. Return on an empty list line ends the list. Widget tests: *Heading* styles only the cursor's line; bold applies to the selection.
- [x] 2.5 Checklist circles tick with one tap while reading and save at once, in the accent; test it.
- [x] 2.6 Share sends the note's plain words to the phone's share sheet; ⋯ has *Copy* and, for a voice note, *Play*.

## 3. Sending a change (phone)

- [x] 3.1 `store.dart`: add `editedAt` to `LocalNote` and `editNote()`. A sent note gets one `note.update` outbox item that replaces any waiting one; an unsent note changes its waiting `notes` item. Tests in `mobile/test/store_test.dart`.
- [x] 3.2 `api.dart`/`outbox.dart`/`sender.dart`: send `note.update` as `PATCH notes` with `clientId` in the body, with new files' bytes after; a 404 or 400 drops the change, so it never holds back the uploads behind it. `webhook.dart`: sign and send `note.updated` (and `note.file` for new files) in own-webhook mode. Tests for both modes, offline then online sending only the latest words.

## 4. The server

- [x] 4.1 `schema/space-migrations/0010_note_edits.sql`: add `relay_notes.edited_at`. Test in `space-schema.test.ts`.
- [x] 4.2 `app/worker/apps/relay/edit-note.ts`: `PATCH notes` with `clientId` in the body, for device keys; finds the note by device and client id (another device's → 404); updates text and `edited_at`; adds new files; logs one `note.updated` unless the words are unchanged. Register it in `api.ts`. Tests: change, same words logs nothing, another device refused, phone-only key reach.
- [x] 4.3 `webhooks/format.ts`: `note.updated` carries optional `edited_at` and `attachments`; update `site/public/webhooks/v1.schema.json` and `receiver.mjs` to drop *no longer sent*; update `relay-webhooks` tests that expect no `note.updated`. Run `npm run relay:api-doc` in `app/`.

## 5. Icons

- [x] 5.1 Replace every `Icons.*` in `mobile/lib` with the `CupertinoIcons.*` from design.md, `BackToNotes` included. Add a test that fails on any `Icons.` left in `mobile/lib`.

## 6. Docs

- [x] 6.1 Update `site/src/content/docs/app/your-notes.md` (editing, styles, checklists, a change to a sent note is sent) and the webhooks page (`note.updated` is sent again). Update `wiki/relay-spaces.md` for `0010`.

## 7. Checks

- [x] 7.1 `flutter analyze` and `flutter test` in `mobile/`; `npm test` in `app/`; `node scripts/product-name.test.mjs`; `node scripts/public-check.mjs`.
- [x] 7.2 `/save`, then on staging: edit a sent note from a phone build and confirm the page shows the new words and a test webhook gets one `note.updated`.
- [x] 7.3 The iPhone device check shows the editing, Aa and reading states; compare them to Apple Notes and fix gaps before publishing.

## 8. Review fixes

- [x] 8.1 The note page marks a new note kept only once an add kept it, so words typed after an add that kept nothing, such as a file over 25 MB alone, add the note again; a note of only files is added with no words, not `#`. Widget test.
- [x] 8.2 Leaving sends only after the save still being written; widget test.
- [x] 8.3 The connect and scan pages use `BackToNotes`, and the place picker draws no check, so no page draws a Material icon by default. `icons_test.dart` walks the pages on Android and iPhone and fails on any icon from Material's font.
- [x] 8.4 Italic on part of a word is written `*foo*bar` and reads back as italic; a whole word keeps `_`; `snake_case` and `* ` bullets stay as typed. Stars pair as the writer nests them. Round-trip tests, and a test of 3,000 random mixes of styles; it found spaces that opened a mark, now fixed.
- [x] 8.5 In own-webhook mode, `note.updated` carries the same `created_at` as `note.created`: when the phone kept the note. Fixture and webhooks page updated.
- [x] 8.6 Two code blocks that touch get an empty line between them when read, so they stay two after an edit; test.
- [x] 8.7 Tasks 3.2 and 4.2 say what was built: `PATCH notes` with `clientId` in the body, and a 404 or 400 drops the change.
- [x] 8.8 The webhooks page says a phone note's `created_at` equals its `recorded_at`, matching what the phone sends.
- [x] 8.9 The note's Title, Heading, Subheading and Body styles name the brand font, so they draw in Inter, not the system font.
- [x] 8.10 A note left with no words and no files is deleted from the phone, as Apple Notes does: a new note that was added then emptied, and an old note emptied. Any waiting upload or change of it leaves the outbox; a note already on the server keeps its last words there. Widget and store tests.
- [x] 8.11 *Aa* lets go of the cursor the normal way, and each style tap tells the editor not to ask for the keyboard, so the panel stays in the keyboard's place on an iPhone; ✕ brings the cursor and keyboard back, and ✓ on the panel closes it and sends. Widget tests.
- [x] 8.12 The Home and folders redesign, email notes and photos came in from main: Home and each folder open the editor, with the back button naming the page it goes back to; every new icon is a `CupertinoIcons` one; the space step is now `0010_note_edits`, and a staging space that ran it as `0008_note_edits` skips it. Phone, server and schema tests.
- [x] 8.13 The iPhone tour's Settings flow scrolls *Sending* to the middle of Home before it taps it, because main's new *Photos* folder put it under Search, and the tap opened the search box.
- [x] 8.14 The iPhone check's fixed tour gains `note-styles`: a new note, *Aa*, Heading and Bold with the Format panel still up after each tap, ✕ brings the bar back, then Done and Back. Claude's hand-run steps each start the test tool again and stall for minutes, so the tour proves *Aa* on every run.
- [x] 8.15 Gaps from the iPhone check: the Format panel's line chips light the line's style at once, as they read it on each draw, and the panel takes the keyboard's full height, measured only while the cursor is in the note, so Bold, the lists and indent show without a scroll. Widget tests.
