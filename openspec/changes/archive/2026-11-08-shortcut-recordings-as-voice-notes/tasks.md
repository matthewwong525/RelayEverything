## 1. iPhone action

- [x] 1.1 In `mobile/ios/Runner/RelayIntents.swift`, change `AddNoteIntent.parameterSummary` to `Summary("Add \(\.$text) with \(\.$files) to Relay Everything")`.
- [x] 1.2 In `AddNoteIntent.perform`, when `files` holds exactly one audio file (`UTType` conforms to `.audio`) within 25 MB, convert it with `AVAudioFile` and `AVAudioConverter` to 16 kHz mono 16-bit PCM WAV at `<support>/shortcuts-inbox/<id>/voice.wav`, and send `recording: {path: "shortcuts-inbox/<id>/voice.wav", durationMs}` with an empty `files` list, in both the engine call and the inbox JSON. On any conversion error, delete the partial WAV and keep today's plain-file path. The fallback `RelayNoteEntity` for the inbox path is kind *Voice* with no files.

## 2. Phone app (Dart)

- [x] 2.1 Add `RelayController.keepRecording` in `mobile/lib/controller.dart`: keep a pending voice note with the typed words, then move its WAV to `voice/<id>.wav`, pinned as `keepNote` pins, skip an id already kept, and write its words at once when `voice` parts exist.
- [x] 2.2 In `mobile/lib/shortcuts/bridge.dart`, `add` calls `keepRecording` when the request has `recording`; in `mobile/lib/shortcuts/inbox.dart`, `InboxRequest` reads `recording`, and `load`'s drain calls `keepRecording` for it.
- [x] 2.3 In `mobile/lib/data/store.dart`, `setWords` puts the note's typed words first, then a newline and the written words; in `_write`, empty written words keep a note that has typed words (words pending cleared, recording kept), and drop one without them as today.
- [x] 2.4 Tests in `mobile/test/`: the bridge keeps a request with `recording` as a pending voice note with the typed words; the written words follow the typed words; no speech keeps a note with typed words and drops one without; an inbox request with `recording` becomes a voice note on `load` and its WAV is not deleted as stray; a request with a recording and other files stays plain files (`shortcuts_test.dart` and the controller tests).

## 3. Website and docs

- [x] 3.1 In `site/src/content/docs/app/shortcuts.md`, say that a lone recording becomes a voice note with typed words first, that its words are written when the app is open, and add a recipe *A voice note from Record audio*. In `site/src/content/docs/app/voice-notes.md`, add one line that a recording from Shortcuts becomes a voice note, linking to the recipe.

## 5. Review fixes

- [x] 5.1 In `mobile/ios/Runner/RelayIntents.swift`, give `RelayAudio.Problem` its `case` keyword, and read the new Swift once more for other compile errors: the converter's error is thrown as `Error?`, and the `recording` dictionary has an explicit `[String: Any]` type.
- [x] 5.2 In `mobile/test/shortcuts_test.dart`, add a test that keeps a shortcut's note and moves its WAV into `voice/` after the sweep reads the kept recordings and before it lists the folder; it fails without the `store.keepsRecording` guard.
- [x] 5.3 Keep the note page's typed words above *Writing the words…* and *Try again* (`mobile/lib/screens/note.dart`), logged as `Assumed` in the proposal.

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs`, and `node scripts/product-name.test.mjs`.
- [x] 4.2 `/save`, and confirm the iOS CI build compiles the Swift change.
