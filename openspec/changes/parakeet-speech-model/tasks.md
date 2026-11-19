# Tasks

## 1. The speech engine

- [x] 1.1 In `mobile/pubspec.yaml`, remove `whisper_cpp_flutter_plus` and add `sherpa_onnx` (2.0.x) and `archive` (4.x); run `flutter pub get` and verify `flutter analyze` names only the whisper uses that group 2 replaces.
- [x] 1.2 Remove the `-Wl,-u,_wf_*` lines from Runner's `OTHER_LDFLAGS` in `mobile/ios/Runner.xcodeproj/project.pbxproj`, and set `SPEECH_PARTS` in `mobile/ios/fastlane/Fastfile` to the five sherpa-onnx names in design.md Decision 5; verify `grep -c _wf_ mobile/ios/Runner.xcodeproj/project.pbxproj` prints 0.

## 2. The model list and its download

- [x] 2.1 In `mobile/lib/voice/model.dart`, add `SpeechModelInfo`, `speechModels` and `currentSpeechModel` with the Parakeet small values from design.md (address, sizes, every SHA-256), and make `SpeechModel` take a `SpeechModelInfo`; verify with a test that the current model's file sizes add to 136,490,421 and its download is 108,035,095.
- [x] 2.2 Download the archive with `Range` resume into `<id>.tar.bz2.part`, check its SHA-256, then unpack in an isolate only the listed files into `<id>.part/`, check each file's SHA-256, delete the archive and `.tar`, and rename the folder to `<id>/`; progress runs 0–90% for the download and 90–100% for the unpack. Verify in `mobile/test/voice_test.dart` with a small `.tar.bz2` built in the test: a good archive becomes ready; a bad archive checksum and a bad file checksum each delete what came and fail `damaged`; a stopped download resumes from its `.part`.
- [x] 2.3 In `load()`, delete every entry of `speech-model/` that is not the current model's folder or its parts, before it reads *ready*; verify with a test that a phone holding `ggml-base.en-q5_1.bin` and its `.part` loads as `missing` with both gone, and that `remove()` deletes the folder and all parts.
- [x] 2.4 Split `Relay.modelBytes` into the download size for the ask and the on-phone size for Settings (`controller.dart`, `relay.dart`, `web_relay.dart`, `hold_to_talk.dart`, `settings.dart`); verify in `mobile/test/screens_test.dart` that the ask says *103 MB* and Settings says *130 MB*, as on the plan's pages.

## 3. The transcriber

- [x] 3.1 In `mobile/lib/voice/transcriber.dart`, replace `WhisperTranscriber`, `_Whisper` and `whisperConfig` with `SherpaTranscriber`: a worker isolate that loads the model's `OfflineRecognizer` once (`nemo_transducer`, CPU, 2 threads), reads the WAV, decodes it, and returns the text through `cleanWords`; a failed run drops the worker (`dropsEngine`), and a time-limit cancel kills it. Make `whyNoWords` no longer name `WhisperException`. Verify in `mobile/test/voice_test.dart` with a fake engine: words come in order, a failure lets the next note get its words, a time-out kills only that job, and `close()` lets the engine go.
- [x] 3.2 Wire it in `mobile/lib/main.dart` and update `mobile/test/fakes.dart` and `mobile/test/controller_test.dart`; keep `mac_imports_test.dart` and `web_imports_test.dart` failing on a `sherpa_onnx` import in place of `whisper_cpp_flutter_plus`; verify `flutter test` passes in `mobile/`.
- [x] 3.3 Run the real model once with `sherpa_onnx` on this machine (a `.scratch/` Dart script or `flutter test` tagged so CI skips it) on the archive's `test_wavs/0.wav`; verify it prints the sentence with punctuation, and note the load and decode times in the proposal's Decision log.

## 4. Words people read

- [x] 4.1 Update `site/src/content/docs/app/voice-notes.md` (Parakeet small by NVIDIA under CC-BY-4.0 with a link to its card, 103 MB download, 130 MB on the phone, the sherpa-onnx release on GitHub as the source), `settings.md` (frees 130 MB) and `privacy.md` (GitHub sees the download, not Hugging Face); verify `node scripts/product-name.test.mjs` passes and no `57 MB` or `whisper` stays in `site/`.
- [x] 4.2 Update `mobile/README.md`, `mobile/ios/fastlane/metadata/review_information/notes.txt`, `wiki/relay-watch.md`, `wiki/development/device-check.md` and `wiki/open-source.md` for sherpa-onnx (no Metal note; the dynamic framework keeps its names); verify `grep -rni "whisper\|57 MB"` over those files finds only history that the text names as old.

## 5. Checks

- [x] 5.1 Run `flutter analyze` and `flutter test` in `mobile/`, and `node scripts/public-check.mjs`; verify all pass.
- [ ] 5.2 `/save`, then verify the phone builds in CI pass, the iPhone build's speech-parts check passes, and report the `.ipa` size beside the last build's.
- [ ] 5.3 With `/verify`, run the device check with `--flows voice-note,recording-card`; verify the ask shows *103 MB* and, where the simulator can, a voice note gets its words.
