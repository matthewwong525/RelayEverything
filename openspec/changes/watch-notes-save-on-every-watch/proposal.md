# Watch notes save on every Apple Watch, and the app opens on the recording screen

**Status:** in-progress
**Branch:** fix-watch-phone-connection
**Open questions:** none

## Why

A voice note from your Apple Watch Series 8 never reaches your phone. The link to the phone is not the cause: the watch app stops at the moment it saves, so there is no note to send. When you tap to save, the app closes to the watch face. When you leave the app to save, the same stop happens out of sight.

The cause is one number. The watch writes the time of the note in milliseconds, and that number is too large for the number type on a Series 8 and older watches. Newer watches, and the test watch the build uses, hold large numbers, so every test passed.

Also, the app shows *Tap to record* for a moment each time it opens, before the recording screen. That flash is jarring.

## What Changes

- **A watch note saves on your watch.** The watch writes the time in a number type that is large on every Apple Watch. On a Series 4 to 8, an SE or the first Ultra, a tap now shows *Saved*, and the note goes to your iPhone as planned.
  ```mermaid
  flowchart TD
    T["Tap to save"] -->|Today| C["App closes"]
    T -->|After| S["Saved"] --> P["On your iPhone"]
  ```
- **The app opens on the recording screen.** No *Tap to record* first: the clock and the bars are there from the first moment, and the bars start to move when the microphone is on. When you come back to the app, it opens the same way, not on the last *Saved* screen. *Tap to record* shows only after you tap the *X*. These pictures are drawn from the app's own colours, font and sizes, because this computer can't run a watch.
  ```picture
  Today, as it opens: pictures/today-open.png
  After, as it opens: pictures/after-open.png
  After, as you talk: pictures/after-talk.png
  ```
- **The note gets to your iPhone sooner when you leave the app.** Today the watch wakes the iPhone app only at the save. When you leave the app to save, the watch app is off the screen by then, and the wake can fail. The watch now also wakes the iPhone app when the recording starts and when you start to leave. A note still waits safely on the watch if the iPhone does not answer.
  ```mermaid
  sequenceDiagram
    participant W as Watch
    participant P as iPhone
    W->>P: Wake up (recording starts)
    W->>P: Wake up (you start to leave)
    W->>P: Recording
    P-->>W: Kept: "On your iPhone"
  ```
- **Each build checks the watch app for older watches.** The build now also makes the watch app and its tests the way a Series 8 runs them. It is a partial check, and the plan says so:
  | The check | Result |
  |---|---|
  | A number written in the code that is too large for an older watch | The build fails |
  | A number that becomes too large while the app runs, as this one did | Not found: no test watch runs as an older watch |
  | The real proof | Your Series 8, on the next TestFlight build |
- **The wiki keeps the lesson.** The watch page says that numbers are small on a Series 8 and older, that the test watch never shows it, and to write times in the large number type.

Non-goals: no change on the iPhone app, no change to the website or the app's guide (they already say the app records when it opens), no new screen.

## What the build needs

- **Your Apple Watch and the next TestFlight build**: Ready. After publish, open the app on your Series 8, talk for 5 seconds, and tap. You must see *Saved*, then *On your iPhone*, and the note in the phone app.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-watch`: a note saves on every Apple Watch model that runs the app; the app opens on the recording screen with no other screen first.
- `relay-app-builds`: the build check compiles the watch app and its tests for the older, 32-bit Apple Watch.

## Impact

- `mobile/ios/RelayWatch/WatchNotes.swift`: `WatchNote.createdAt` is `Int64`; a `.starting` screen and the open and leave rules in `WatchRules`; `PhaseRule` gives a wake on `.inactive`.
- `mobile/ios/RelayWatch/WatchModel.swift`, `WatchScreens.swift`: start on `.starting`, drawn as the recording screen at 0:00; back to `.starting` on leave; wake at record start and on `.inactive`.
- `mobile/ios/RelayWatchTests/RelayWatchTests.swift`: the 64-bit time, the open and leave rules, the wake moments.
- `mobile/device-check/watch-tests.sh`: an `arm64_32` compile of the watch app and its tests before the simulator tests. It runs in `mobile-ios.yml` and `mobile-device-check.yml`.
- `wiki/relay-watch.md`: the 32-bit rule and the wake moments.
- No change to `mobile/ios/Runner/`: the iPhone reads the time as an `NSNumber`, which holds an `Int64`.

## Decision log

- **2026-11-11** — Asked which Apple Watch you have and what it showed after a tap → chose: Series 8 on watchOS 26.4, build 279; the app closes to the watch face. This confirms the stop at save on a 32-bit watch.
- **2026-11-11** — Asked for more → chose: remove the *Tap to record* flash when the app opens.
- **2026-11-11** — Assumed: the app opens on the recording screen at 0:00 with the bars at rest, not on an empty screen, because the screen then does not change shape when the recording starts.
- **2026-11-11** — Assumed: on leave, the screen goes back to the opening look, so a return shows no *Saved* or *Not saved* flash; a save that failed on leave is told by the wrist tap only, because the person has left and the next open records a new note at once.
- **2026-11-11** — Assumed: the time is an `Int64`, not text or a decimal number, because the iPhone already reads it as a whole number and needs no change.
- **2026-11-11** — Assumed: the wake at record start and at the start of a leave is added without proof, because no check on this computer can make a watch talk to a phone; the note's safe wait on the watch does not change, so a wrong guess costs nothing.
- **2026-11-11** — Assumed: the 32-bit compile is worth its minute in each build though it cannot find a stop at run time, because it is the only automatic check that sees the older watch at all.
- **2026-11-11** — Assumed: the website and the app's guide need no change, because they describe what the person does and sees, and that is the same.
- **2026-11-11** — Assumed: the wake test checks the one shared helper, `WatchSender.wakeIfNear`, that `WatchModel` calls at record start and at `.inactive`, because `WatchModel` needs a microphone and is not in the test target.
- **2026-11-11** — Assumed: the 32-bit compile uses `build-for-testing` with no automatic fall back to `build`, because a silent fall back could hide a test that does not compile; if CI shows the unsigned test bundle can not build, change it to `build` then.
- **2026-11-11** — Built: the watch time is an `Int64`, the app opens on the recording look (`.starting`), a wake goes at record start and at `.inactive` while recording, `watch-tests.sh` compiles for `arm64_32` first, and the wiki says why. The review found one gap, the wiki not naming every watch on watchOS 10 or 11 as 32-bit; fixed. The Swift is first compiled by CI.
