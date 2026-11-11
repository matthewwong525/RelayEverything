# Tasks

## 1. The speech engine (`mobile/lib/voice/`)

- [x] 1.1 Make `whisperConfig` give `WhisperBackend.cpu` on iOS, on a phone and on the simulator, and the default elsewhere; update its test in `mobile/test/voice_test.dart` and verify it passes.
- [x] 1.2 Make `WhisperTranscriber.write` dispose and drop its engine when a run fails, but keep it when the app cancelled the run at the time limit; put the choice in a small function that a test can call with no native engine, add its tests to `voice_test.dart`, and verify they pass.

## 2. The controller and the note page (`mobile/lib/controller.dart`, `relay.dart`, `screens/note_editor.dart`)

- [x] 2.1 Keep each failed note's reason beside its failed mark, made from the error as the design says, and give it to `Entry.why`; add tests to `mobile/test/controller_test.dart` for a time limit, an engine code and any other error, and verify they pass.
- [x] 2.2 Make `resume()` write failed notes again, and add `wordsSettled()`; add a `controller_test.dart` test that a note which failed gets its words after `resume()` and that a note being written is not written twice, and verify it passes.
- [x] 2.3 Add a `controller_test.dart` test that a second note gets its words after the first note's write fails, and verify it passes.
- [x] 2.4 Show `Why: <reason>` on a failed note's page between the failed line and **Try again**, only when there is a reason; extend the failed-note test in `mobile/test/screens_test.dart` and verify it passes.

## 3. The watch hand-off (`mobile/lib/shortcuts/bridge.dart`, `mobile/ios/Runner/`)

- [x] 3.1 Make the `inboxChanged` handler in `bridge.dart` answer only after the inbox is drained and the words it started are settled; add a test to `mobile/test/shortcuts_test.dart` that the answer waits for the words, and verify it passes.
- [x] 3.2 In `RelayWatchReceiver.swift` and `RelayIntents.swift`, hold a background task from the file's arrival until `inboxChanged` answers or the task expires, ended at most once; verify by reading that every path ends the task, since Swift is first compiled in CI.

## 4. The guide and the wiki

- [x] 4.1 Update `site/src/content/docs/app/voice-notes.md`: the *Why* line, the try on return to the app, and that a watch note gets its words with the phone locked; verify `node scripts/product-name.test.mjs` passes.
- [x] 4.2 Update the voice notes lines of `mobile/README.md` (the processor writes the words on an iPhone) and add to `wiki/relay-watch.md` the lesson: an iPhone refuses graphics work off screen, a failed engine must be made again, and the app asks for time at the hand-off; verify the wiki check passes.

## 5. Checks

- [x] 5.1 Run `flutter analyze` and `flutter test` in `mobile/` and verify both pass.
