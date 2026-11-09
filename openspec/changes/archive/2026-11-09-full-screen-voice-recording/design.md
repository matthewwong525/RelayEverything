# Design

## Context

Read against main at bc0ace5; the build first takes main. `ListeningOverlay` in `mobile/lib/screens/hold_to_talk.dart` is a card at the bottom of a 35% scrim, put in the root overlay by `home.dart` whenever `Relay.listening` is set (a hold or Shortcuts). A tap on the scrim calls `Relay.endVoiceNote`; *Cancel* calls `Relay.cancelVoiceNote`. `NewNoteButton`, in `timeline.dart`'s bottom bar, is a 52 px accent circle with `CupertinoIcons.square_pencil`, turning into a spark `CupertinoIcons.mic_fill` while live; `test/icons_test.dart` fails on any Material `Icons.` in `lib/`. The `Microphone` in `voice/recorder.dart` wraps `record`'s `AudioRecorder`, which has `onAmplitudeChanged(Duration)` returning dBFS. Small app state is kept by `Store.set(key, value)` in the `state` table.

The plan *open-voice-note-after-save* (workspace premium-giraffe) also edits `_save` in this file: it opens the note's page after a save. It gives `ListeningOverlay` a required `onSaved(DateTime at)`, called from `_save`, and `home.dart` opens the note with it. The two compose: `RecordingScreen` keeps that callback and its save path, and whichever lands second keeps the other's behavior.

## Goals / Non-Goals

**Goals:** a full-screen recording view with a live level; a clear save (tap anywhere) and cancel (X top right); *New note* that shows it records.

**Non-Goals:** a pause button; keeping the level or a waveform; a separate mic button; where the app goes after a save.

## Decisions

- **Same overlay entry, full-screen widget.** Keep the root `OverlayEntry` in `home.dart` so Shortcuts still cover any open page. Rename `ListeningOverlay` to `RecordingScreen`: an opaque `ColoredBox(brand.paper)` inside `SafeArea`, a `GestureDetector` with `HitTestBehavior.opaque` that saves, and the X as its own button that does not pass the tap through. Alternative: push a route. Rejected: the overlay already covers every case, and a route would fight the plan above, which pushes the note page after a save.
- **Back saves.** Wrap the screen in a `PopScope(canPop: false, onPopInvokedWithResult: …save)` installed while listening, so Android back and the iOS edge swipe on a page underneath save instead of leaving the page. Because the overlay is not a route, register the handler on the root navigator's current route via a `PopScope` in `home.dart`'s build while `relay.listening != null`.
- **Level stream.** Add `Stream<double> levels()` to `Microphone`: `PhoneMicrophone` maps `onAmplitudeChanged(100 ms)` from dBFS (−60…0) to 0…1; the test fake emits a fixed list. `Relay` exposes `Stream<double>? get level` while listening. At each new level, all 17 bars follow the current level at once, tallest in the middle: bar *i* is `max(floor, full × (1 − |i − 8| / 10) × level)`, times a small per-bar difference of 0.75 to 1 that the count of levels sets, so tests see the same heights each time. This matches the prototype the person approved; a history of the last 17 levels showed new sound late and small. With `MediaQuery.disableAnimations`, bars jump with no `AnimatedContainer` easing.
- **Hold ring.** `NewNoteButton` uses `onLongPressDown` to start a 500 ms `AnimationController` that draws a spark arc round the button (`CustomPainter`), `onLongPressCancel` resets it. The long press itself still fires at `kLongPressTimeout`, so the ring length reads that constant, not a second number.
- **Icons.** The button keeps `CupertinoIcons.square_pencil` with no badge: a corner mark looked odd, so the tip and the ring carry the hint. The recording screen uses `CupertinoIcons.xmark` for the X. Semantics stay: label *New note*, custom action *Record a voice note*; the X is labelled *Cancel*; the screen body is labelled *Save the voice note*.
- **Tip flag.** Store key `holdTipSeen`; `Relay.holdTipSeen` reads it at start and `startVoiceNote` sets it on its first success, so a hold, Shortcuts, or the Action button all end the tip. The tip is a small ink bubble above the button, hidden while search is open.

## Risks / Trade-offs

- `onAmplitudeChanged` on a WAV recording is supported on iOS and Android in `record` 7; if a platform returns no values, the bars stay at their floor and the timer still runs. A test covers a silent stream.
- The opaque screen hides snack bars shown under it; save and cancel messages show after it closes, as now.

## UX

### Use-case brief

Matthew, or anyone with the app, wants to speak a quick thought, often while walking, with one hand. Done is a saved voice note with nothing left on screen. Common case: hold, talk 5–30 s, tap. Edge cases: cancel; a Shortcuts or Action button start; the 5-minute limit; no speech. Mirrors Apple's Voice Memos and the iOS dictation sheet, in the brand's paper and amber.

### Flow

Hold *New note* → ring closes, buzz → full-screen recording → tap anywhere → back on the list (or the note page, by the other plan). X → back on the list, nothing kept.

### Hierarchy

Recording screen: the one action is *tap anywhere to save*, said in the largest text at the bottom; the timer and bars confirm it is live. The X is small, quiet, and at the corner. Notes list: *New note* stays the one bright button; the tip is quiet, and the ring shows only while held.

### Review

[review.html](review.html): *Recording fills the whole screen* holds the prototype for both screens; *New note shows that it also records* holds the flow.

### Components

Existing: `brandOf` colors, `clockOf`, `AccentGlow`, `Store.set`. New: `RecordingScreen` (replaces `ListeningOverlay`), `_LevelBars`, `_HoldRing` painter, `_HoldTip` bubble, all in `hold_to_talk.dart`.
