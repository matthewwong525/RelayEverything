# Design

## Context

See proposal.md, Why. The voice path is `Controller._write` → `WhisperTranscriber.words` → `whisper_cpp_flutter_plus` 0.5.1.

- `WhisperTranscriber._words` calls `Isolate.run(() => WhisperAudio.readWav(wav))` inside an instance method. The closure's context can hold `this`, and `this` holds `_last`, a `Future`. A `Future` can not cross to an isolate, so `Isolate.run` throws `ArgumentError`. That is an `Error`, not an `Exception`.
- `Controller._write` catches only `on Exception`. An `Error` leaves the job's future failed, the note stays `words_pending`, and nothing tells the person.
- The package looks up 22 `wf_*` symbols with `DynamicLibrary.process()` on iOS. Its bridge is a static `whisper.xcframework`, and under SwiftPM its plugin keeps only `wf_version` referenced. A Release link with dead stripping can drop the other symbols. A missing symbol is also an `ArgumentError`, at the first `WhisperEngine.load`.
- Nothing can run an iPhone build here (Linux). The iOS CI job runs on macOS.

## Goals / Non-Goals

**Goals:**
- Remove both possible causes, and fail visibly if a third one shows.
- Make the iOS build fail before TestFlight when a looked-up symbol is missing.

**Non-Goals:**
- No change of speech package or model.
- No on-device integration test in CI.

## Decisions

1. **Read the WAV through a top-level function.** `Future<Float32List> _readWav(String path) => Isolate.run(() => WhisperAudio.readWav(File(path)))` sits outside the class, so its closure holds only `path`. Alternative: `compute` from Flutter: the same fix, but the transcriber stays free of a Flutter import.
2. **`_write` catches every error; the transcriber owns the time limit.** `on Object catch (error, stack)`: the error and stack go to `debugPrint`, the note's id goes in an in-memory `_wordsFailed` set, and the app shows a notice. The limit is `max(2 minutes, recording length)`, passed as `Transcriber.words(wav, limit:)`. The base `Transcriber` writes one recording at a time, in order. The limit starts when that recording's own job starts, or when the job before it passes its limit: a stuck job that cancel does not stop so can not hold the notes behind it on *Writing the words…*. A recording that passes its limit before its job starts never starts it. On time-out it cancels only that job's `WordsJob`: `WhisperTranscriber` then cancels that job's `WhisperTask`, or starts none if the WAV or model still loads. `transcribe` returns before the native run starts in its new isolate, and `wf_run` clears the cancel flag as it starts, so a cancel in that gap is lost. Once cancelled, `WhisperTranscriber` calls `task.cancel` again every 100 ms until the result comes. `task.result.whenComplete` stops that timer; the package frees the native job in its own listener on the same result, registered first, in the same turn, so no tick reaches a freed job. Alternative: a `Future.timeout` in the controller and a `cancel()` that stops whatever runs: a queued note's limit then runs while it waits, and its time-out cancels a different note. Alternative: a `failed` column in the store: a failure is a fact about this run of the app, and the next open must try again anyway, so memory is enough.
3. **Try again.** `Entry` gets `failed`, from `_wordsFailed`. `Relay.writeWordsAgain()` copies the set, clears it, and runs `_writePending(only: failed)` through `_track`, so a note whose words are being written now is not written twice. The card shows the failed text and a `Try again` button in place of *Writing the words…* and the progress bar.
4. **Keep the symbols linked, and global.** Runner's Release and Profile `OTHER_LDFLAGS` get `-Wl,-u,_wf_<name>` for each of the 22 symbols the package looks up, and `STRIP_STYLE = "non-global"`. Alternative: turn off `DEAD_CODE_STRIPPING` for the whole app: larger app, and it does not help when the linker never pulls the archive member. `-u` makes the linker pull and keep each symbol. An archive strips *All Symbols* by default, which removes the global symbols `DynamicLibrary.process()` looks up, and `-u` can not stop that; *Non-Global Symbols* keeps them, as Flutter's iOS FFI guide says. If the link fails because a symbol is not in the archive, that symbol leaves the list, as the package then can not use it on iOS either.
5. **Check the symbols in the exact file sent to TestFlight.** In `mobile/ios/fastlane/Fastfile`, between `build_app` and `upload_to_testflight`, `check_speech_parts` unzips the `.ipa` at `lane_context[SharedValues::IPA_OUTPUT_PATH]` to a temporary folder, runs `nm -gU` on `Payload/Runner.app/Runner` (and the frameworks in `Runner.app/Frameworks`, if the package builds as one), removes the folder, and fails the lane if `_wf_run`, `_wf_context_create`, `_wf_job_create` or `_wf_last_error` is missing. The four are the ones `transcribe` needs. Alternative: check the archive's `Runner.app`: the export from the archive can strip again, so that is not the file `upload_to_testflight` sends. Alternative: check `build/ios/iphoneos/Runner.app` from `flutter build ios` in the workflow: `build_app` links and strips again, so that is not the binary TestFlight gets either. One check, in one place, keeps one copy of the list.

## UX

The note card has one new state, *failed*, beside *writing* and *done*:

- **Writing:** *Writing the words…* and a progress bar, as now.
- **Failed:** *The words did not come. Your recording is safe.* and a **Try again** button. **Play** stays.
- **Done:** the words, as now.

A notice says the same once, when the words fail: *The words did not come. Tap Try again on the note.*

## Risks / Trade-offs

- [Neither fix is the real cause] → The note now says it failed and logs the error, so the next build shows the cause in the Xcode console or a TestFlight crash log, not a silent wait.
- [`-u` names a symbol the archive lacks, and the link fails] → CI shows it on the pull request; drop that symbol from the list.
- [Cancel does not stop a stuck native call] → The note still shows failed after the limit, and so do the notes behind it, each after its own limit. `Try again` queues behind the stuck job; the next app open starts fresh.

## Migration Plan

None. A note stuck on build 2 is still `words_pending` and gets its words at the first open of the new build.
