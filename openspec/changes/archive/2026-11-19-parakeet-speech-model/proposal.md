# Proposal: Voice notes use Parakeet small

**Status:** ready-to-ship
**Branch:** compare-parakeet-small-voice-model
**Open questions:** none

## Why

The phone writes a voice note's words with whisper.cpp's small English model. NVIDIA's Parakeet small gets fewer words wrong, is much faster, and adds full stops, commas and capitals. It is still small enough to keep on a phone. We also want to offer more speech models later, so the app must know a model as one item from a list, not as one fixed file.

## What Changes

- **Voice notes write their words with Parakeet small, on the phone, with no server.** The words come faster and with punctuation. Everything else stays the same: the recording screen, *Try again*, the time limit, and sending.
  ```mermaid
  flowchart LR
    A[Recording] --> B[Parakeet small on the phone] --> C[Words with punctuation]
  ```
- **The first voice note asks for a 103 MB download, not 57 MB.** The phone gets it once, from the page where the speech engine's makers keep their models, and checks it against fixed checksums. On the phone it takes 130 MB.
  ```page
  Before: pages/before-ask.html
  After: pages/after-ask.html
  ```
- **Settings shows the new size, and *Remove* frees 130 MB.**
  ```page
  Before: pages/before-settings.html
  After: pages/after-settings.html
  ```
- **After the update, the phone deletes the old 57 MB model.** The next voice note asks to get the new one. Notes you already made keep their words. A note whose words did not come gets them from the new model on *Try again*.
- **The app knows its speech model as one item from a list**, so a later change can add more models, and a choice of model, with no new download code. This change adds no choice on screen.
- **The website, the privacy page and the App Store review notes say the same.**
- **Not in this change:** a test of Parakeet against whisper on your own voice notes (later), a model choice on screen (later), and voice notes on the Mac.

## What the build needs

- **Nothing.** The model files and the speech engine are public, and need no key.

## Decision log

- **2026-11-18** — Asked whether to switch to Parakeet small → chose to switch now, and to test it against whisper on real voice notes later.
- **2026-11-18** — Asked for more models later → chose a list of models in the code now, with one item and no choice on screen.
- **2026-11-18** — Assumed: the transducer build of Parakeet small (`parakeet_tdt_transducer_110m-en-36000-int8`), not its CTC build, because both are about the same size and both gave the same words in a test here, but NVIDIA's numbers favour the transducer, and it ended *I love you* with a full stop where CTC did not.
- **2026-11-18** — Assumed: the phone gets the model from the sherpa-onnx release on GitHub, the speech engine's own makers, because no trusted page holds the unpacked files, and our own copy would be a second thing to keep.
- **2026-11-18** — Assumed: whisper.cpp leaves the app, because sherpa-onnx also runs Whisper, Moonshine and other models, so one engine serves every model a later list adds.
- **2026-11-18** — Assumed: the old model is deleted on the first open after the update, because it is 57 MB the app no longer uses.
- **2026-11-19** — Assumed: the unpack streams the bzip2 straight into the tar reader and writes only the four files, with no `.tar` file on disk, because it lowers the peak space from about 380 MB to about 240 MB and needs one file fewer to clean up; design.md Decision 2 named a `.tar` step.
- **2026-11-19** — Assumed: the app reads the WAV in Dart (`soundOfWav`), not with sherpa-onnx's reader, because the recorder can leave the `data` size unwritten, and the Dart reader already reads such a file to its end.
- **2026-11-19** — Assumed: `sherpa_onnx` resolved to 2.0.2 inside the planned 2.0.x range; its iPhone framework and the five function names are the same.
- **2026-11-19** — Ran the real model with `sherpa_onnx` from Dart on this Linux computer (`test/real_speech_model_test.dart`, which skips with no archive, so CI skips it): the phone's own unpack of the real archive took 26 s, the first note (load and decode) 3.6 s, and the next note 0.46 s, all in a debug build. Text: *Well, I don't wish to see it any more, observed Phoebe, turning away her eyes. It is certainly very like the old portrait.* The bzip2 unpack alone took 30 s in a compiled build here, so a phone can take about a minute: Risks already names the fix.
- **2026-11-19** — Check: `test/real_speech_model_test.dart` skips unless `RELAY_SPEECH_ARCHIVE` and `RELAY_SPEECH_WAV` are set, because CI has no 103 MB model and must not download one; the fake-engine tests in `voice_test.dart` cover the same code paths on every run.
- **2026-11-19** — Check: `.github/workflows/mobile-android.yml` drops whisper.cpp's native build paths from the Android build's cache, because whisper.cpp leaves the app and sherpa-onnx comes built; the NDK and Gradle cache stay.
- **2026-11-19** — Assumed: the time limit ends the note's wait and sends the worker its stop message, and a failed run disposes the worker, in place of the `Isolate.kill` that design.md Decision 4 named, because `sherpa_onnx` sets no native finalizer, so a killed worker keeps its 130 MB model in memory until the app closes (found in review).
- **2026-11-19** — Assumed: the Mac app keeps `sherpa_onnx_macos`, about 58 MB, though it has no voice notes, and a check confirms that the Mac build in CI passes and the built app opens, because `sherpa_onnx` names its Mac package for every app that uses it, and only a copy of the plugin could leave it out. Its podspec links the library into the app (`vendored_libraries`), so a build step that deletes it would stop the Mac app from opening.
- **2026-11-19** — Checkpoint: built, reviewed twice (memory fix, update-scenario test, Mac size accepted); local checks pass; saved for the phone builds in CI (task 5.2) and the device check (task 5.3).
- **2026-11-19** — Saved as PR #158: every check passed, all three phone builds too, and the iPhone build's check said *All speech parts are in the build*. A branch build keeps no `.ipa`, so its size is not known; the Mac build's file grew from 28 MB to 49 MB, the Mac speech library this plan accepted.
- **2026-11-19** — iPhone device check on `732c742` ([run](https://github.com/matthewwong525/RelayEverything/actions/runs/44573916834)): the ask says *103 MB*, the voice-note step got the model and passed, and the recording-card step's card showed *No words heard* (the simulator's microphone is silent), so the engine ran. The tour ended `broken` on a later recording-card tap that is out of scope: since #153 the title's tap area spans the card, so a tap on *Fab call* opens no keyboard. Verdict: UNKNOWN, no contradiction of this change's scenarios.
- **2026-11-19** — Archived for publishing; the main spec `relay-voice-notes` already holds this change's requirement.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-voice-notes`: the speech model is now a set of files the phone unpacks and checks one by one, and the update removes the old model.

## Impact

- `mobile/pubspec.yaml`: `whisper_cpp_flutter_plus` goes; `sherpa_onnx` and `archive` come in.
- `mobile/lib/voice/model.dart`: a list of speech models; download, resume, unpack and checks for a model of several files; old-model clean-up.
- `mobile/lib/voice/transcriber.dart`: a sherpa-onnx transcriber in a long-lived background isolate.
- `mobile/lib/main.dart`, `mobile/lib/controller.dart`: the new model and transcriber.
- `mobile/ios/Runner.xcodeproj/project.pbxproj`, `mobile/ios/fastlane/Fastfile`: whisper's link flags go; the build check looks for sherpa-onnx's functions.
- `mobile/test/`: `voice_test.dart`, `controller_test.dart`, `screens_test.dart`, `fakes.dart`, `mac_imports_test.dart`, `web_imports_test.dart`.
- `site/src/content/docs/app/voice-notes.md`, `settings.md`, `privacy.md`; `mobile/README.md`; `mobile/ios/fastlane/metadata/review_information/notes.txt`.
- `wiki/relay-watch.md`, `wiki/development/device-check.md`, `wiki/open-source.md`.
- No server, route or data change. The app grows by the speech engine's library, about 26 MB on an iPhone before compression.
- The Mac app grows by `sherpa_onnx_macos`, a library of about 58 MB for Apple silicon and Intel that the Mac app never uses: `sherpa_onnx` brings it in for every platform.
