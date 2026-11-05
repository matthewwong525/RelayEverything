# Tasks

## 0. Before the build

- [x] 0.1 Confirm `relay-offline-by-default` is on `origin/main` (`openspec/specs/relay-sending/spec.md` exists, and `mobile/lib/data/sender.dart` and `settings.dart` are there); merge `origin/main` into this branch. Verify `openspec validate relay-voice-notes --strict --no-interactive` passes with no archive warning for `relay-sending`, and the *The app works offline by default* text in `specs/relay-sending/spec.md` matches the main spec except for the voice exception.

## 1. Speech engine and model (`mobile/lib/voice/`)

- [ ] 1.1 Add the whisper.cpp binding (first choice `whisper_cpp_flutter_plus`; fallbacks in design.md), `record` and `just_audio` to `mobile/pubspec.yaml`; verify `flutter pub get`, `flutter analyze`, and an Android debug build pass, and write the build-time cost in the Decision log.
- [x] 1.2 Write `lib/voice/transcriber.dart`: the `Transcriber` interface, the whisper implementation in a background isolate, and the no-speech cleaning; with `test/voice_test.dart` covering the cleaning (`[BLANK_AUDIO]`, `(music)`, blank, real words). Verify the tests pass.
- [x] 1.3 Write `lib/voice/model.dart`: states `missing/asking/downloading/ready/failed`, resumable download through a `.part` file, SHA-256 check against a fixed constant, no iCloud backup, and `remove()`; with tests using a fake HTTP client for success, a resumed drop, a wrong checksum, and remove. Verify the tests pass and no request carries the device key.
- [x] 1.4 Write `lib/voice/recorder.dart`: 16 kHz mono WAV to `<support>/voice/<clientId>.wav`, the 500 ms floor, cancel, and the 5-minute cap; with tests on a fake recorder. Verify the tests pass.

## 2. Notes and sending

- [x] 2.1 Add `kind`, `audioPath`, `durationMs` and `wordsPending` to the `notes` table with a schema step and defaults; verify a store test opens an earlier-version database and reads its notes as `typed`.
- [x] 2.2 Add the voice-note flow to the controller: save with `wordsPending`, write words, drop the note and file when empty, enqueue only with words and sending on, and redo pending rows on start; with controller tests for each spec scenario in `relay-voice-notes` (fake transcriber). Verify the tests pass.
- [x] 2.3 Make the earlier-notes prompt skip notes still waiting for words; verify a controller test where a pending voice note enqueues only after its words land.
- [x] 2.4 Change the offline change's fail-on-any-call test so it allows only the model URL, only after *Get it*; add a test that a voice note with sending off makes no other request. Verify both pass.

## 3. Screens

- [x] 3.1 Add `HoldToTalkButton` and the listening card to the timeline, the *Voice* chip, *Writing the words…*, the play button, and the *No speech heard* message; with widget tests for hold, short press, slide-off, and a written note. Verify the tests pass.
- [x] 3.2 Add the *Get the speech model?* dialog, the progress card, the failed state with *Try again*, and the microphone-permission refused line; with widget tests for *Not now*, *Get it*, and failure. Verify the tests pass.
- [x] 3.3 Add the *Voice notes* section to Settings with the model's state, size and *Remove*; with a widget test that *Remove* returns the timeline button to the first-time dialog. Verify the test passes.
- [ ] 3.4 Add `NSMicrophoneUsageDescription` to `ios/Runner/Info.plist` and `RECORD_AUDIO` to `android/app/src/main/AndroidManifest.xml`; verify both files hold them and the Android build passes.

## 4. Docs and website

- [ ] 4.1 Write `site/src/content/docs/app/voice-notes.md` and add `app/voice-notes` to `site/sidebar.mjs` after `app/your-notes`; update `app/your-notes.md`, `app/settings.md` and `privacy.md` by design.md. Verify the site's own tests pass and `node scripts/publish-relay-site.mjs --ref HEAD --staging` prints `result=` without `refused`.
- [x] 4.2 Add *Voice notes* to *What it does* in `mobile/README.md`; verify it names no key and no private address.

## 5. Final check

- [x] 5.1 Run `flutter analyze` and `flutter test` in `mobile/`, `openspec validate relay-voice-notes --strict --no-interactive`, and `node scripts/public-check.mjs` (must print `result=clean`); verify all pass.
- [ ] 5.2 After `/save`, check that the pull request's Android build passes and makes the `.apk` file. The iPhone check (first voice note downloads the model, a 10 s note in airplane mode gets its words, a pocket bump saves nothing, with sending on only the words reach the server) waits on TestFlight: it is a Decision-log line and an open thread, not this task.

## 6. Review findings

- [x] 6.1 A microphone that does not start no longer stops voice notes until a restart: `VoiceRecorder.start` sets its state only after the microphone starts and deletes the file when it fails; the controller clears `_starting` in a `finally` and returns *The microphone did not start. Try again.*; `endVoiceNote` and `cancelVoiceNote` do not rethrow the failed start. Verify recorder and controller tests for a failing start, then a press that records.
- [x] 6.2 Recordings stay out of phone backups: `voice/` is excluded in `backup_rules.xml` and `data_extraction_rules.xml`, and on iOS each kept recording is marked through the `relay/files` channel; *Play* on a recording that is not on the phone, such as after a move to a new phone, says so. Log the decision and say so in `voice-notes.md`, `privacy.md` and `mobile/README.md`. Verify recorder tests for the mark and the controller test for a missing recording.
- [x] 6.3 With a screen reader, the *Hold to talk* button's tap opens the first-time question when the model is not ready, and a finger's tap still asks once. Verify the widget tests.
