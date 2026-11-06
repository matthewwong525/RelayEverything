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
2. **`_write` catches every error and has a time limit.** `on Object catch (error, stack)`: the error and stack go to `debugPrint`, the note's id goes in an in-memory `_wordsFailed` set, and the app shows a notice. The limit is `max(2 minutes, recording length)` through `Future.timeout`. On time-out the controller calls `Transcriber.cancel()`, a new method (no-op by default), and `WhisperTranscriber` cancels its running `TranscriptionTask`. Alternative: a `failed` column in the store: a failure is a fact about this run of the app, and the next open must try again anyway, so memory is enough.
3. **Try again.** `Entry` gets `failed`, from `_wordsFailed`. `Relay.writeWordsAgain()` clears the set and runs `_writePending()` through `_track`. The card shows the failed text and a `Try again` button in place of *Writing the words…* and the progress bar.
4. **Keep the symbols linked.** Runner's Release and Profile `OTHER_LDFLAGS` get `-Wl,-u,_wf_<name>` for each of the 22 symbols the package looks up. Alternative: turn off `DEAD_CODE_STRIPPING` for the whole app: larger app, and it does not help when the linker never pulls the archive member. `-u` makes the linker pull and keep each symbol. If the link fails because a symbol is not in the archive, that symbol leaves the list, as the package then can not use it on iOS either.
5. **Check the symbols in CI.** After `flutter build ios --release`, a step runs `nm -gU build/ios/iphoneos/Runner.app/Runner` (and the frameworks in `Runner.app/Frameworks`, if the package builds as one) and fails if `_wf_run`, `_wf_context_create`, `_wf_job_create` or `_wf_last_error` is missing. The four are the ones `transcribe` needs.

## UX

The note card has one new state, *failed*, beside *writing* and *done*:

- **Writing:** *Writing the words…* and a progress bar, as now.
- **Failed:** *The words did not come. Your recording is safe.* and a **Try again** button. **Play** stays.
- **Done:** the words, as now.

A notice says the same once, when the words fail: *The words did not come. Tap Try again on the note.*

## Risks / Trade-offs

- [Neither fix is the real cause] → The note now says it failed and logs the error, so the next build shows the cause in the Xcode console or a TestFlight crash log, not a silent wait.
- [`-u` names a symbol the archive lacks, and the link fails] → CI shows it on the pull request; drop that symbol from the list.
- [Cancel does not stop a stuck native call] → The note still shows failed after the limit. `Try again` queues behind the stuck job; the next app open starts fresh.

## Migration Plan

None. A note stuck on build 2 is still `words_pending` and gets its words at the first open of the new build.
