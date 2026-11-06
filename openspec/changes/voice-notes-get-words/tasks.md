## 1. Phone app

- [ ] 1.1 In `mobile/lib/voice/transcriber.dart`, read the WAV through a top-level function given only the path, and add `Transcriber.cancel()` (no-op by default; `WhisperTranscriber` cancels its running `TranscriptionTask`).
- [ ] 1.2 In `mobile/lib/controller.dart`, make `_write` catch every error (`on Object`), log it with `debugPrint`, add the time limit (the longer of 2 minutes and the recording's length) with cancel on time-out, keep failed note ids in memory, and show the notice once.
- [ ] 1.3 Add `Entry.failed` and `Relay.writeWordsAgain()` in `mobile/lib/relay.dart` and the controller; show the failed text and the **Try again** button on the note card in `mobile/lib/screens/timeline.dart`.
- [ ] 1.4 Tests in `mobile/test/`: a transcriber that throws an `Error` leaves no note on *Writing the words…* and shows the notice; a transcriber that never ends hits the time limit and calls `cancel`; **Try again** writes the words; the card shows the failed state. Update `fakes.dart` for the new members.

## 2. iPhone build

- [ ] 2.1 In `mobile/ios/Runner.xcodeproj/project.pbxproj`, add `-Wl,-u,_wf_<name>` to Runner's Release and Profile `OTHER_LDFLAGS` for each `wf_*` symbol the package looks up.
- [ ] 2.2 In `.github/workflows/mobile-ios.yml`, after the build, fail the job if `nm -gU` on the app binary (and its frameworks) lacks `_wf_run`, `_wf_context_create`, `_wf_job_create` or `_wf_last_error`.

## 3. Docs

- [ ] 3.1 Change the App Store Connect key access from App Manager to Admin in `.env.example` and `mobile/README.md`, with the reason: cloud signing needs Admin.
- [ ] 3.2 Add the failed state and **Try again** to `site/src/content/docs/app/voice-notes.md`.

## 4. Checks

- [ ] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, and `node scripts/public-check.mjs`.
- [ ] 4.2 `/save`, and confirm the iOS CI build passes with the symbol check.
- [ ] 4.3 After publish, Matthew installs the new TestFlight build and records a short voice note; its words fill in.
