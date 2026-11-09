# Tasks

## 1. Sound level and the tip flag

- [x] 1.0 Bring this workspace up to main, after #72 (Account in Settings) and #73 (voice note opens on save) if they have landed, because both change `home.dart` and the screen tests; then check each file named below and in the proposal's Impact still exists where it says.
- [x] 1.1 Add `Stream<double> levels()` to `Microphone` in `mobile/lib/voice/recorder.dart`: `PhoneMicrophone` maps `onAmplitudeChanged(Duration(milliseconds: 100))` dBFS −60…0 to 0…1, clamped; give the test fake in `mobile/test/fakes.dart` a settable list of levels.
- [x] 1.2 Expose the level while listening on `Relay` (`relay.dart`, `controller.dart`), and the `holdTipSeen` flag kept by `Store.set`; set it on the first voice note that starts, from a hold, Shortcuts or the Action button.
- [x] 1.3 In `mobile/test/controller_test.dart`, test that the flag is false at first, true after `startVoiceNote` succeeds, still true after a new controller reads the same store, and unchanged when the start fails; and that the level stream ends when the note is saved or cancelled.

## 2. The recording screen and New note

- [x] 2.1 In `mobile/lib/screens/hold_to_talk.dart`, replace `ListeningOverlay` with `RecordingScreen`: paper background over the whole app, *Listening* with a spark dot, a large `clockOf` timer, 17 level bars in spark, *Tap anywhere to save* and *Saves by itself at 5:00*, and a round X (`CupertinoIcons.xmark`, labelled *Cancel*) at the top right; keep the save and cancel guards as they are, and the `onSaved(DateTime at)` callback and its save path if *open-voice-note-after-save* has landed.
- [x] 2.2 Make the back gesture save while listening, through a `PopScope` in `home.dart` while `relay.listening != null`; keep the root overlay entry.
- [x] 2.3 Give `NewNoteButton`, with its icon unchanged, the hold ring that fills over `holdToTalk` and resets on an early lift, and the *Hold to talk* tip while `holdTipSeen` is false and search is closed; bars ease only when animations are on.
- [x] 2.4 In `mobile/test/screens_test.dart`, update the listening tests for the new screen, and add tests: a tap in the middle saves; the X keeps nothing and does not also save; the back gesture saves; the tip shows before the first voice note and not after; the ring shows while held and resets on an early lift; a silent level stream keeps the bars at their floor; the semantics labels *Save the voice note*, *Cancel*, *New note* and *Record a voice note*.

## 3. Device check, docs and website

- [x] 3.1 Update the device check as it is after #68: in `mobile/device-check/flows/new-note.yaml`, which `tour.sh` runs, assert the *Hold to talk* tip on first open; add the hold, a save by tap, and a cancel by X to the scenarios Claude runs through `flow.sh`, and keep `steps.mjs` and its tests passing.
- [x] 3.2 Update `mobile/README.md` (voice notes and Shortcuts lines) and `site/src/content/docs/app/voice-notes.md`, `your-notes.md` and `shortcuts.md`: the full-screen recording, the X, the ring on *New note* and the *Hold to talk* tip; verify `node scripts/product-name.test.mjs` passes.

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`, `node scripts/public-check.mjs`, and the wiki link check; verify all pass.
- [ ] 4.2 `/save`, then run the iPhone device check with a hold on *New note*, a save by tap, and a cancel by X, in light and dark; show its pictures beside the prototype on the preview page.

## 5. Review fixes

- [x] 5.1 Give the hold ring's `AnimationController` in `hold_to_talk.dart` `AnimationBehavior.preserve`, so with *Reduce motion* on it still fills over the whole hold, not in 25 ms; test that it is at about 0.5 after 250 ms of holding with `disableAnimations: true`.
- [x] 5.2 Test that a side swipe on `RecordingScreen` saves: the fake's calls are `['voice start', 'voice end']`.
- [x] 5.3 Make `LevelBars` draw all 17 bars from the current level, tallest in the middle, with a small per-bar difference set by the count of levels, as in the approved prototype; update the bar tests, keep the silent-stream test, and update design.md's *Level stream* and the Decision log.
- [x] 5.4 Centre the recording screen: its `Stack` expands, so the column fills the screen; a test checks the time, the bars and the save line sit mid-screen (found by the iPhone check, content hugged the left edge).
- [x] 5.5 Load whisper.cpp on the CPU on the iPhone simulator, where the Metal driver traps on model load and the app crashed after a save and at each launch; a real phone keeps the default; with a test of `whisperConfig`. Find the simulator by the app's own path, which holds `/CoreSimulator/`: the `SIMULATOR_DEVICE_NAME` flag did not reach the app the iPhone check opens, and it crashed the same way.
