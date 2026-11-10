# Keep a voice note from your Apple Watch

**Status:** in-progress
**Branch:** legit-puma
**Open questions:** none

## Why

You get an idea when your phone is in a pocket, a bag or another room. Today you must take out the phone to keep it. With a Relay Everything app on your Apple Watch, you raise your wrist, talk, and the note is kept, with the same private speech-to-words the phone uses.

## What Changes

- **A Relay Everything app on the watch: tap, talk, tap to save.** The app opens on one big amber mic button. Tap it and the watch records, with a clock and bars that follow your voice. Tap anywhere to save, or the *X* to keep nothing. The watch buzzes and shows *Saved*. A recording of less than one second keeps nothing, and a recording stops itself at 5 minutes, as on the phone. The watch app comes with the iPhone app: install it from TestFlight, and it shows on the watch. No real picture: this computer can't run a watch, so these are sketches.
  ```screen
  <div class="row gap">
    <div class="card col gap">
      <span class="muted">Relay Everything</span>
      <button class="btn-primary">Talk</button>
      <span class="muted">2 notes wait for your iPhone</span>
    </div>
    <div class="card col gap">
      <div class="row gap"><span class="grow">0:12</span><button class="btn-ghost">X</button></div>
      <div class="skeleton"></div>
      <span class="muted">Tap to save</span>
    </div>
    <div class="card col gap">
      <h3>Saved</h3>
      <span class="muted">Sending to your iPhone</span>
    </div>
  </div>
  ```
- **Your iPhone keeps the note and writes the words.** The watch hands the recording to your paired iPhone. The iPhone keeps it as a voice note and writes its words on the phone, with no speech service on any network, as for a note you hold to record. It then shows in *Voice notes*, and it syncs only if you signed in. It works signed out and with no signal. When the iPhone is away or off, the note waits on the watch and goes when they are near again; the watch shows how many notes wait. The recording goes only from the watch to your iPhone, never to Relay Everything or Apple.
  ```mermaid
  sequenceDiagram
    participant W as Watch
    participant P as iPhone
    participant R as Relay Everything
    W->>W: Record and save
    W->>P: Recording (when near)
    P->>P: Keep note, write words
    P-->>W: Kept
    P->>R: Words only, if signed in
  ```
- **Start a voice note from the watch face.** Add the Relay Everything button to a watch face: one tap opens the watch app already recording. On an Apple Watch Ultra, set the Action button to the *Start a voice note* shortcut for the same result.
  ```mermaid
  flowchart LR
    F["Watch face button"] --> Rec["Recording"]
    A["Ultra Action button"] --> Rec
    App["App list"] --> Talk["Talk button"] --> Rec
  ```
- **The guide and the website explain it.** The phone app's guide and the website's *Voice notes* page say how to get the watch app, start a note, and where the note goes.

Non-goals: no typed or dictated notes on the watch, no list of notes on the watch, no sending from the watch straight to Relay Everything, no Wear OS watch, and no health or places from the watch app (Apple Health already gives the phone the watch's steps, heart rate and sleep).

## What the build needs

- **Apple's App Store Connect key and signing certificate**: Ready, in `.env` and the repository secrets. The build uses them to register the watch app with Apple and get its profile.
- **An Apple Watch paired to your iPhone**: Needs you, only to try it. This computer builds and tests the watch app on a watch simulator in CI; the real check is a TestFlight build on your watch.
  ```form
  text: Your Apple Watch model and watchOS version (or none)
  ```

## Capabilities

### New Capabilities

- `relay-watch`: a watchOS app that records a voice note, hands it to the paired iPhone, waits while the iPhone is away, and starts from a watch face button or the Action button.

### Modified Capabilities

- `relay-voice-notes`: a recording from the watch becomes a voice note on the iPhone, with its words written on the phone.
- `relay-app-builds`: the iPhone build also signs and ships the watch app with its own App Store profile.

## Impact

- `mobile/ios/RelayWatch/` (new): a SwiftUI watchOS app target (watchOS 10+), bundle id `com.matthewwong525.relayApp.watchkitapp`, embedded in `Runner.app`; `AVAudioRecorder` writes 16 kHz mono WAV; `WCSession.transferFile` sends it with `{id, createdAt, durationMs}`; a WidgetKit accessory widget and an App Intent `StartVoiceNoteIntent` open recording.
- `mobile/ios/Runner/AppDelegate.swift` and a new `RelayWatchReceiver.swift`: a `WCSessionDelegate` that moves each file into `shortcuts-inbox/<id>/voice.wav` with `<id>.json`, and tells Dart to drain the inbox when the app runs.
- `mobile/lib/shortcuts/inbox.dart`, `mobile/lib/controller.dart`: drain the inbox on a watch message and on resume, not only at start.
- `mobile/ios/Runner.xcodeproj/project.pbxproj`: the watch and widget targets, *Embed Watch Content*.
- `mobile/ios/fastlane/Fastfile`: `SIGNED_TARGETS` gains the watch app and its widget; a lane step registers their bundle ids once with the App Store Connect key.
- `.github/workflows/mobile-ios.yml`, `mobile-device-check.yml`: the Swift tests also run on a watch simulator.
- Tests: Swift tests for the watch queue and the receiver; a Dart test for draining on resume.
- Docs: `mobile/README.md`, `site/src/content/docs/app/voice-notes.md`, `wiki/development/device-check.md` if its Swift tests change.

## Decision log

- **2026-11-10** — Asked what the watch app should do → chose voice notes only: tap, talk, tap to save, with the iPhone writing the words.
- **2026-11-10** — Asked how a watch note reaches your notes → chose through the paired iPhone, with no new key, waiting on the watch while the iPhone is away.
- **2026-11-10** — Asked whether the watch face gets a button → chose yes: a watch face button, and the *Start a voice note* shortcut for the Ultra's Action button.
- **2026-11-10** — Assumed: the watch app is native Swift, not Flutter, because Flutter does not build for watchOS.
- **2026-11-10** — Assumed: the iPhone keeps a watch note through the same inbox folder Shortcuts uses, because the app already keeps each inbox note once by its id and writes a voice note's words from its `voice.wav`.
- **2026-11-10** — Assumed: the watch app needs watchOS 10 or later, because its watch face button uses WidgetKit and watchOS 10 runs on every watch from Series 4.
- **2026-11-10** — Assumed: a watch note keeps no place, because the watch app asks for no location and the phone's pin is for notes made on the phone.
- **2026-11-10** — Assumed: shortest and longest recordings match the phone (1 second, 5 minutes), because one rule for voice notes is easier to learn.
- **2026-11-10** — Assumed: a watch note's time is when you tap to save on the watch, not when the iPhone gets it, because the iPhone can be away for hours.
- **2026-11-10** — Assumed: `mobile-ios.yml` gains its own `watch-tests` job on a Mac, because the signed build job runs only with the Apple secrets and the watch tests need none.
- **2026-11-10** — Assumed: the device check's simulator build names the booted iPhone with `-d`, because Flutter refuses a simulator build of an app with a watch companion when no device is named.
- **2026-11-10** — Check: `.github/workflows/mobile-device-check.yml` builds the simulator app with `-d` and runs `RelayWatchTests` after `RunnerTests` in job `swift-tests`, because the watch app needs both; nothing is loosened, and a failed watch test fails the job.
- **2026-11-10** — Check: `.github/workflows/mobile-ios.yml` gains job `watch-tests`, because the watch app's tests need a watch simulator; nothing is loosened.
- **2026-11-10** — Checkpoint: the watch app, the iPhone receiver, the Fastfile and CI steps, and the docs are written; Flutter analyze and 567 tests pass. The Swift, the Xcode project and the Fastfile were written on Linux and never compiled; this save's Mac CI is their first build.
