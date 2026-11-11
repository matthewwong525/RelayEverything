# Tasks

## 1. Watch app: save on every watch, open on the recording screen, wake sooner

- [x] 1.1 In `mobile/ios/RelayWatch/WatchNotes.swift`, make `WatchNote.createdAt` an `Int64` (property, initializer, decode) and make it in `WatchQueue.add` with `Int64((at.timeIntervalSince1970 * 1000).rounded())`. Read every other `Int` in `mobile/ios/RelayWatch/` and `mobile/ios/RelayWatchWidget/` and confirm none can pass `Int32.max`. Verify: `grep -n "Int(" mobile/ios/RelayWatch/*.swift` shows no time made as `Int`; a new `RelayWatchTests` case asserts `MemoryLayout.size(ofValue: note.createdAt) == 8` and that the metadata's `createdAt` as `NSNumber` gives the same `int64Value`.
- [x] 1.2 In `WatchNotes.swift`, add `.starting` to `WatchScreen`, and `WatchRules.atOpen(allowed:)` and `WatchRules.afterLeave(_:)` as the design says. Add `.wake` to `PhaseRule.Action`, given for `.inactive` while not away. Verify: new `RelayWatchTests` cases for `atOpen` (true, nil, false), `afterLeave` (each screen) and `PhaseRule` (inactive while open gives wake; inactive while away gives nothing).
- [x] 1.3 In `WatchModel.swift`, start `screen` from `WatchRules.atOpen`, apply `afterLeave` on `.background` after `save()`, and send a wake, only when reachable, after `record()` starts and on `.wake` while recording. In `WatchScreens.swift`, draw `RecordingScreen` for `.starting` with the clock at 0:00 and the level at 0; a tap there calls `talk()`. Update the file comments that name the first screen. Verify: the watch app compiles in CI; a `RelayWatchTests` case with the fake sender shows a wake at record start when reachable and none when not.
- [x] 1.4 In `mobile/ios/RelayWatchTests/RelayWatchTests.swift`, keep the present cases passing with the `Int64` time. Verify: the `watch-tests` job runs all cases with 0 failures.

## 2. Build check: compile for the 32-bit watch

- [x] 2.1 In `mobile/device-check/watch-tests.sh`, before the simulator tests, compile the `RelayWatch` scheme for `generic/platform=watchOS` with `ARCHS=arm64_32` and signing off (`build-for-testing`; fall back to `build` if the test bundle can not build unsigned, and say so in the comment). Log to `$OUT/watch-32bit.log`; a compile error fails the script. Verify: the `watch-tests` job log shows `arm64_32` compile lines for `RelayWatch` before the tests, and the job passes.

## 3. Wiki

- [x] 3.1 In `wiki/relay-watch.md`, add: `Int` is 32 bits on Series 8 and older and on any watch before watchOS 26, the simulator never shows it, write times as `Int64`; the build compiles for `arm64_32` but can not run it; the wake goes at record start, at `.inactive` and at save, and why. Verify: `node scripts/product-name.test.mjs` passes and the page stays under 3,000 words.

## 4. Checks

- [x] 4.1 `/save`, then confirm in CI: the signed iPhone build with the watch app passes, and `watch-tests` passes with the 32-bit compile. Follow-up after publish, not a task: Matthew opens the app on his Series 8 with the next TestFlight build, talks 5 seconds and taps, and sees *Saved*, then *On your iPhone*, and the note in the phone app.
