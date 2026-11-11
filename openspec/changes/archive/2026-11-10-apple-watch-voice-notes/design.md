# Design

## Context

The phone app is Flutter. Flutter does not build for watchOS, so the watch app is a native SwiftUI target inside `mobile/ios/Runner.xcodeproj`, embedded in `Runner.app`, the same way `ShareExtension` sits beside Runner today.

The phone already has a path for a voice note made outside the Flutter screen: `ios/Runner/RelayIntents.swift` writes `shortcuts-inbox/<id>.json` and `shortcuts-inbox/<id>/voice.wav` (16 kHz mono WAV), and `lib/controller.dart` drains it with `drainInbox` at start, keeping each note once by its 32-hex id and writing its words with whisper.cpp. The watch reuses this path whole.

Signing: `ios/fastlane/Fastfile` signs each entry of `SIGNED_TARGETS` with the one saved Apple Distribution certificate and a fetched App Store profile. `get_provisioning_profile` needs the bundle id to exist on Apple's account. The App Store Connect key is in the primary worktree's `.env` and in the repository secrets.

## Goals / Non-Goals

**Goals:**
- Record on the watch, hand the WAV to the iPhone, keep it once as a voice note, words written on the phone.
- Notes wait on the watch, durably, while the iPhone is away.
- A watch face button and an App Intent for the Ultra's Action button.
- CI builds, signs and tests the watch app with no new secret.

**Non-Goals:**
- Typed or dictated notes, a notes list, direct sending with a watch key, Wear OS, health or location from the watch.

## Decisions

### Transport: WatchConnectivity `transferFile`

The watch calls `WCSession.default.transferFile(url, metadata: ["id", "createdAt", "durationMs"])`. The system queues it, survives restarts, retries when the phone is reachable, and wakes the iPhone app in the background to receive it. Alternatives: `sendMessage` needs both apps live; a watch device key sending to the server breaks *offline by default* and was declined.

The watch keeps its own queue file (`Application Support/watch-queue/<id>.wav` plus a JSON index) and deletes a recording only when the iPhone answers with `transferUserInfo(["kept": id])`, not when `session(_:didFinish:error:)` ends its transfer: that says the iPhone's system has the file, but only `kept` says the note is in the inbox. While the app runs, a saved note sends only notes never sent or whose transfer failed. At each launch, and when the session becomes ready, the watch sends again every note with no transfer in `outstandingFileTransfers`, on its way or delivered too, because a transfer the system dropped, or a `kept` lost when the person moves to a new iPhone, gives no callback, and the note would wait forever. A second copy is harmless: the iPhone keeps the ids of the last 500 watch notes it took in `Application Support/watch-received.json`, written before it answers `kept`, and for an id on that list it answers `kept` again and writes nothing, so a note the person deleted on the iPhone does not come back. A failed transfer goes again at the next saved note or launch, not at once: the system already waits for the iPhone, so an error that reaches `didFinish` comes again at once, and an at-once send would loop and use the battery.

### iPhone receive: `RelayWatchReceiver.swift`

A `WCSessionDelegate` activated in `AppDelegate.didFinishLaunching` (before Flutter starts, so a background wake gets it). `session(_:didReceive file:)` checks the id against `^[0-9a-f]{32}$`, moves the file into `shortcuts-inbox/<id>/voice.wav` and writes `<id>.json` in the format `RelayIntents.swift` writes (`text: ""`, `createdAt`, `recording: {path, durationMs}`, `files: []`), adds the id to `watch-received.json`, then answers `kept`; an id already on that list gets `kept` and nothing is written. The move happens inside the delegate call, because the system deletes the file when it returns. When the Flutter engine runs, it calls the existing method channel with `inboxChanged`, and Dart drains at once. Dart also drains on `AppLifecycleState.resumed`, so a note received in the background shows on the next open.

Shared write code moves from `RelayIntents.swift` into a small `ShortcutsInbox.swift` both use, so the JSON shape has one writer.

### Recording on the watch

`AVAudioRecorder` with `kAudioFormatLinearPCM`, 16 kHz, 1 channel, 16 bit, into a `.wav`: the exact format the phone's inbox expects, so the phone needs no conversion. `isMeteringEnabled` drives the bars. Under 1 s → delete; at 5 min → save (the phone's `longest`). `AVAudioSession` category `.record`. An `NSMicrophoneUsageDescription` in the watch's `Info.plist`.

### Watch face button and Action button

A WidgetKit extension (`RelayWatchWidget`) with `accessoryCircular`, `accessoryCorner` and `accessoryInline` families, each a mic glyph with `widgetURL(relay-watch://record)`. The app handles the URL with `onOpenURL` and starts recording. An `AppIntent` `StartVoiceNoteIntent` with `openAppWhenRun = true` and an `AppShortcutsProvider` phrase *Start a voice note in Relay Everything*; the Ultra's Action button runs it as a shortcut.

### Targets and versions

- `RelayWatch` (watchOS app, single-target SwiftUI, watchOS 10.0), bundle id `com.matthewwong525.relayApp.watchkitapp`, `WKCompanionAppBundleIdentifier = com.matthewwong525.relayApp`.
- `RelayWatchWidget`, bundle id `com.matthewwong525.relayApp.watchkitapp.widget`.
- Version and build come from Runner's `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER` through the same xcconfig, because App Store Connect rejects a watch app whose version differs from its iPhone app.
- `RelayWatchTests` for the queue and recorder rules, run on a watch simulator.

### Signing in CI

`SIGNED_TARGETS` gains both targets. A new private lane `ensure_bundle_ids` calls `Spaceship::ConnectAPI::BundleId.find` and `.create` (platform `IOS`, as watch apps register under iOS) for each id before `get_provisioning_profile`, so the first build registers them and later builds find them. No App Group is needed on the watch: it talks only through WatchConnectivity.

## Risks / Trade-offs

- **Background wake is not instant.** iOS decides when to wake the iPhone app for a file. The note may show only at next open. The spec allows this.
- **The first signed build may need a profile Apple can't make at once.** The lane makes it; a failure prints the bundle id and stops before TestFlight.
- **No real watch here.** CI checks the build and the Swift tests on a simulator; the hand-off between two simulators is not tested in CI. The real check is Matthew's watch with a TestFlight build.
- **Words wait for the speech model.** A watch note on a phone with no model is kept with its recording and gets words after the person agrees to the model, as a Shortcuts voice note does today.

## UX

### Use-case brief
Who: Matthew, and later anyone with an iPhone and an Apple Watch. Job: keep a thought in seconds when the phone is out of reach: walking, driving, cooking, in bed. Done: the watch says *Saved*, and the note later shows in *Voice notes* with its words. Common: one short note, iPhone near. Edge: iPhone away (notes wait), microphone refused, a mistaken tap (shorter than 1 s keeps nothing). Frequency assumed: a few notes a day.

### Flow
Watch face button → recording starts → talk → tap anywhere → *Saved* (1 s) → back to the main screen. From the app list: open → *Talk* → the same. Edge branches: *X* keeps nothing; no microphone permission shows *Allow the microphone in Settings › Privacy*.

### Hierarchy
- Main screen: the one action is *Talk*, a large amber round button, as the phone's voice-note ring is amber. The wait count is small and grey, shown only when a note waits.
- Recording screen: the whole screen is the save target; the *X* sits small at the top right, as on the phone's recording screen.
- Saved: a check and *Saved*, then it closes itself.

### Review
[review.html](review.html). The first What Changes item sketches the three watch screens; the third sketches the ways to start.

### Components
SwiftUI on watchOS with the brand's amber and paper colors and the Inter font from `Assets.xcassets`/`Brand.swift`, mirroring the phone's full-screen voice-note recording (`lib/voice/`). New: a sound-bar view in SwiftUI, because the Flutter one can't run on the watch.
