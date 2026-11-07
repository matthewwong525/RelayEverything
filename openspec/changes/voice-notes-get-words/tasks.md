## 1. Phone app

- [x] 1.1 In `mobile/lib/voice/transcriber.dart`, read the WAV through a top-level function given only the path, and add `Transcriber.cancel()` (no-op by default; `WhisperTranscriber` cancels its running `WhisperTask`).
- [x] 1.2 In `mobile/lib/controller.dart`, make `_write` catch every error (`on Object`), log it with `debugPrint`, add the time limit (the longer of 2 minutes and the recording's length) with cancel on time-out, keep failed note ids in memory, and show the notice once.
- [x] 1.3 Add `Entry.failed` and `Relay.writeWordsAgain()` in `mobile/lib/relay.dart` and the controller; show the failed text and the **Try again** button on the note card in `mobile/lib/screens/timeline.dart`.
- [x] 1.4 Tests in `mobile/test/`: a transcriber that throws an `Error` leaves no note on *Writing the words…* and shows the notice; a transcriber that never ends hits the time limit and calls `cancel`; **Try again** writes the words; the card shows the failed state. Update `fakes.dart` for the new members.
- [x] 1.5 Give each note's time limit to its own job: `Transcriber.words(wav, limit:)` writes one recording at a time, starts the limit when that recording's job starts, and on time-out cancels only that job (`WordsJob`); `WhisperTranscriber` starts no engine job for a cancelled one. Test: two notes at once, the second waits past its own limit, and neither is cancelled.
- [x] 1.6 Make **Try again** write only the notes in `_wordsFailed` (copied before it clears), not a note whose words are being written now. Test: one failed note and one being written; Try again writes the failed one only.
- [x] 1.7 Free the queue's clock from a stuck job: in `Transcriber.words`, a waiting note's limit starts when the job before it ends or passes its own limit, and a note past its limit before its job starts never starts it. Test: a fake whose cancel does not end the held words, two notes; the second ends failed, not writing.
- [x] 1.8 Keep a cancel that comes as the engine starts: in `WhisperTranscriber.write`, once cancelled, call `task.cancel` again every 100 ms until the result comes, and stop the timer from `task.result.whenComplete` (the package frees the native job in its own listener on the result, in the same turn, before this one).

## 2. iPhone build

- [x] 2.1 In `mobile/ios/Runner.xcodeproj/project.pbxproj`, add `-Wl,-u,_wf_<name>` to Runner's Release and Profile `OTHER_LDFLAGS`, after the flags already there, for each `wf_*` symbol the package looks up.
- [x] 2.2 After the build, fail the job (now in `mobile/ios/fastlane/Fastfile`, see 2.3–2.5) if `nm -gU` on the app binary (and its frameworks) lacks `_wf_run`, `_wf_context_create`, `_wf_job_create` or `_wf_last_error`.
- [x] 2.3 Add `STRIP_STYLE = "non-global";` to Runner's Release and Profile build settings, so the archive keeps the global symbols the package looks up.
- [x] 2.4 Move the symbol check to the archive TestFlight gets: in `mobile/ios/fastlane/Fastfile`, between `build_app` and `upload_to_testflight`, fail the lane if the archived `Runner.app/Runner` and its frameworks lack `_wf_run`, `_wf_context_create`, `_wf_job_create` or `_wf_last_error`; remove the workflow step, so the list has one copy.
- [x] 2.5 Check the exact file sent to TestFlight: `check_speech_parts` unzips the `.ipa` at `lane_context[SharedValues::IPA_OUTPUT_PATH]` to a temporary folder, runs `nm -gU` on `Payload/Runner.app/Runner` and its frameworks, and removes the folder.

## 3. Docs

- [x] 3.1 Change the App Store Connect key access from App Manager to Admin in `.env.example`, with the reason: cloud signing needs Admin.
- [x] 3.2 Add the failed state and **Try again** to `site/src/content/docs/app/voice-notes.md`.

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, and `node scripts/public-check.mjs`.
- [ ] 4.2 `/save`, and confirm the iOS CI build passes with the symbol check.
- [ ] 4.3 After publish, Matthew installs the new TestFlight build and records a short voice note; its words fill in.
