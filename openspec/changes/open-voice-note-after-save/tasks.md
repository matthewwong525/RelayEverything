## 1. Phone app

- [x] 1.1 In `mobile/lib/screens/hold_to_talk.dart`, give `ListeningOverlay` a required `onSaved(DateTime at)`; in `_save`, read `_relay.listening` before `endVoiceNote()` and call `onSaved` when the result is `null`.
- [x] 1.2 In `mobile/lib/screens/home.dart`, pass `onSaved` from `_showListening`: find the voice entry with that `at` in `relay.entries` and open `NoteEditor` with `openPage`; do nothing when none is found.
- [x] 1.3 In `mobile/lib/screens/note_editor.dart`, when a kept note is no longer in `relay.entries`, mark the page deleted so leaving saves nothing, and pop it once, after the frame.
- [x] 1.4 Tests in `mobile/test/screens_test.dart`: a tap to save opens the note page and Back shows the list; a save from a shortcut over another page opens the note page on top; Cancel and a too-short recording open no page; a note page whose entry goes away closes. Update fakes only if a test needs it.
- [x] 1.5 Review fix: in `mobile/lib/screens/note_editor.dart`, keep the `relay.openNote` held before the page opened and give it back on close, so a voice note page opened over another note page leaves that note held. Test in the Shortcuts group: Back from the voice note page gives the hold back to the note page under it.
- [x] 1.6 Review fix: tests in the voice notes group for the page's start from the list as it is now: words already in `entries` show, not *Writing the words…*; a note already gone closes the page at once. Rename the test that a note gone from the list closes its page, which no longer claims a delete on another phone.
- [x] 1.7 In `NoteEditor._compose`, give the hold back before the new page replaces this one, so leaving the new note holds no closed note. Test: open a note, tap *New note*, go back, and no note is held.

## 2. Docs

- [x] 2.1 In `site/src/content/docs/app/voice-notes.md`, say that the tap to save opens the note, where its words fill in.

## 3. Checks

- [x] 3.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`.
- [ ] 3.2 `/save`, and confirm the phone builds pass.
