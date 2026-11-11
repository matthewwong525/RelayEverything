# Design

## Context

See [proposal.md](proposal.md) for why. The facts that shape the fix:

- `WatchQueue.add` in `mobile/ios/RelayWatch/WatchNotes.swift` makes the note's time with `Int(at.timeIntervalSince1970 * 1000)`. Swift's `Int` is the size of a pointer. Apple Watch Series 4 to 8, SE, SE 2 and the first Ultra run the `arm64_32` slice, where `Int` is 32 bits, and so does every watch on watchOS 10 or 11. The value, about 1.79e12, is past `Int32.max`, and `Int(Double)` traps. The trap is before the recording moves into the queue, so nothing waits on the watch.
- Build 279's log (run 43038631543, Xcode 26.6) shows both `arm64-apple-watchos` and `arm64_32-apple-watchos` slices. Series 9 and later on watchOS 26 run the `arm64` slice and do not trap.
- The watch simulator is `arm64` (or `x86_64`): 64-bit. `RelayWatchTests` can never run 32-bit code. Its own literal `1_793_790_000_000` typed as `Int` would not compile for `arm64_32`, which shows the tests were never built for it.
- Matthew's test on 2026-11-11 (Series 8, watchOS 26.4, build 279): a tap while recording closes the app to the watch face.
- At launch `WatchModel.screen` is `.idle` (*Tap to record*). The recording screen comes only after `scenePhase` is `.active` and `AVAudioSession` is active, some hundred milliseconds later. On a return, the last screen (*Saved*) shows the same way before the new recording.
- `WCSession.isReachable` on a watch is true only while the watch app is on screen. The save on leave runs at `scenePhase` `.background`, so its wake can be skipped.

## Goals / Non-Goals

**Goals:**

- A save does not trap on any watch slice.
- The first frame at each open is the recording screen.
- The iPhone app is awake when a save on leave sends its file, where the system allows it.
- CI sees the 32-bit slice at least at compile time.

**Non-Goals:**

- No change in `mobile/ios/Runner/` or in Dart.
- No background task on the iPhone to hold the app open after a wake. Add it only if a real watch shows the note still waits after this change.
- No source lint for `Int(` in Swift: a pattern check gives false alarms and a false sense of safety.

## Decisions

### The time is `Int64`

`WatchNote.createdAt` becomes `Int64`, in the stored property, the initializer and the `Codable` decode. `WatchQueue.add` makes it with `Int64((at.timeIntervalSince1970 * 1000).rounded())`. The metadata dictionary gives it to `transferFile` as an `NSNumber`; the iPhone reads `(metadata["createdAt"] as? NSNumber)?.intValue`, which is 64-bit there, so the iPhone side does not change. `notes.json` holds a JSON number either way, so a queue saved by build 279 on a 64-bit watch still decodes.

`durationMs` (at most 300,000), the clock's `Int(seconds)` and the count in `waitingWords` stay `Int`: each is far below `Int32.max`.

Alternative: keep `Int` and store seconds. Rejected: the iPhone and Dart read milliseconds, and a unit that changes between the two devices is a new way to be wrong.

### A `.starting` screen that looks like the recording

`WatchScreen` gets `.starting`. `WatchRoot` draws `RecordingScreen` for `.starting` and `.recording`. While `.starting`, the clock shows 0:00, the level is 0 (bars at rest), a tap calls `talk()`, not `save()`, and the *X* goes to `.idle` as today.

Two plain rules in `WatchRules`, so `RelayWatchTests` checks them:

- `atOpen(allowed: Bool?) -> WatchScreen`: `.microphoneRefused` for `false`, else `.starting`. `WatchModel` uses it for the first value of `screen`. With `nil`, the system's microphone question shows over the recording look.
- `afterLeave(_ screen: WatchScreen) -> WatchScreen`: `.microphoneRefused` stays, each other screen becomes `.starting`. `WatchModel.phase(.background)` applies it after `save()`.

`talk()` and `record()` keep their guard on `.recording`; `record()` sets `.recording` on success and `.notSaved` on failure, as today.

Alternative: an empty screen at open. Rejected: the layout then jumps when the clock and bars come in, which is a smaller flash but still a flash.

Alternative: start the microphone before the first frame. Rejected: `scenePhase` is not `.active` yet, and a recording that starts off screen breaks the rule that the app records only while the person can see it.

### Wake the iPhone at record start and at the start of a leave

`PhaseRule.enter(.inactive)` gives a new action `.wake` when the app is not away; `WatchModel.phase` sends a wake for it only while `screen == .recording`. `record()` sends a wake after a start. Each wake goes through one helper that checks `link.reachable` first, as the wake at save does. A wake is one small message with no note in it, and the iPhone's `didReceiveMessage` stays a no-op.

A short wrist drop also gives `.inactive`, so it sends one wake too. That costs the iPhone one short background launch and changes nothing the person sees.

### An `arm64_32` compile in the watch tests script

`mobile/device-check/watch-tests.sh` first runs:

```bash
xcodebuild build-for-testing -workspace ios/Runner.xcworkspace -scheme RelayWatch \
  -destination 'generic/platform=watchOS' ARCHS=arm64_32 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO
```

It logs to `$OUT/watch-32bit.log` and fails the script on a compile error. Both callers (`mobile-ios.yml` job `watch-tests`, `mobile-device-check.yml` Swift job) get it with no workflow change. If the test bundle can not build for a device with signing off, fall back to `build` of the app target alone and say so in the script's comment and in the wiki: the app's own code is the part that ships.

One test asserts the type at run time on any simulator: `MemoryLayout.size(ofValue: note.createdAt) == 8`.

## Risks / Trade-offs

- [The Swift here is first compiled on GitHub's Mac] → `/save` after the build, and read the `watch-tests` job before the plan is called done.
- [The 32-bit compile adds about a minute and may need its signing flags tuned] → the fallback above; the tests still run as today.
- [A second trap may sit behind the first on a 32-bit watch] → the audit of every `Int` in `RelayWatch/` and `RelayWatchWidget/` found only the time; the real proof is Matthew's Series 8, named as the follow-up.
- [The wake moments are unproven] → the file transfer is unchanged and keeps the note until the iPhone answers `kept`.
- [The system's picture of the app in the app list may show the recording look while nothing records] → opening the app records at once, so the picture is true by the time the person sees the app.

## Migration Plan

None. A queue file from an older build decodes as before. Rollback is a revert.
