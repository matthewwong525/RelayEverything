# The watch records at once, and every watch note reaches your phone

**Status:** ready-to-ship
**Branch:** fix-watch-app-sync-recording
**Open questions:** none

## Why

Notes from the Apple Watch do not show on the phone. The watch says no note waits, so the phone took them. The likely cause: the phone found no words in the recording and deleted the note, as it does for an empty held voice note. You can't see where a note stopped, so you can't tell. Also, the *Talk* screen is one tap too many: opening the app should start recording.

## What Changes

- **Open the app and it records.** The *Talk* screen goes. Open the watch app, from the app list, the watch face button or the Action button, and it records at once. Tap anywhere to save. Leave the app (press the Digital Crown, or lower your wrist until the clock comes back) and it saves too. The *X* still keeps nothing. Under 1 second keeps nothing, so a quick open and close saves nothing. Each time you come back to the app, a new recording starts. No real picture: this computer can't run a watch, so these are sketches.
  ```screen
  <div class="row gap">
    <div class="card col gap">
      <div class="row gap"><span class="grow">0:04</span><button class="btn-ghost">X</button></div>
      <div class="skeleton"></div>
      <span class="muted">Tap to save</span>
    </div>
    <div class="card col gap">
      <h3>Saved</h3>
      <span class="muted">On your iPhone</span>
      <span class="muted">Tap for a new note</span>
    </div>
  </div>
  ```
- **The watch says when your iPhone has the note.** After you save, the watch shows *Sending to your iPhone*, then *On your iPhone* when the phone kept it. If other notes still wait, it shows how many. If the watch could not save the recording, it says *Not saved* and does not go quietly back.
  ```mermaid
  flowchart LR
    S["Saved"] --> W["Sending to your iPhone"] --> K["On your iPhone"]
    X["Save failed"] --> N["Not saved"]
  ```
- **The phone never throws away a watch note.** When the phone finds no words in a watch recording, it keeps the note as *Voice note* with its recording and *No words heard*, and does not delete it. You can play it to hear what the watch caught. A note with no words stays on the phone and is not sent. A note you hold to record on the phone works as today. No real picture: the row needs the new mark built first; the build adds a screen test that draws it.
  ```screen
  <div class="card col gap phone">
    <span class="tag">Voice</span>
    <h3>Voice note</h3>
    <span class="muted">No words heard · 0:06</span>
  </div>
  ```
- **Faster to the phone.** When the iPhone is near, the watch also wakes the Relay Everything app on the iPhone, so the phone takes the note in seconds, not when the system chooses. The note shows on the phone at once if the app is open, else the next time you open it.
  ```mermaid
  sequenceDiagram
    participant W as Watch
    participant P as iPhone
    W->>P: Recording
    W->>P: Wake up
    P->>P: Keep the note
    P-->>W: Kept: "On your iPhone"
  ```
- **The guide and the website say it.** The phone app's guide and the website's *Voice notes* page say the app records when it opens, and leaving saves.

Non-goals: no new place to see watch notes, no sending from the watch to Relay Everything, no change to how a held voice note on the phone works.

## What the build needs

- **Your Apple Watch and the next TestFlight build**: Ready. CI builds and tests the watch app on a simulator; you try the new build on your own watch after publish.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-watch`: the app records when it opens, saves when you leave, shows when the iPhone has the note, and wakes the iPhone app.
- `relay-voice-notes`: a watch note with no words is kept with its recording, not deleted.

## Impact

- `mobile/ios/RelayWatch/WatchModel.swift`, `WatchScreens.swift`, `RelayWatchApp.swift`, `StartVoiceNoteIntent.swift`, `WatchLink.swift`, `WatchNotes.swift`: no main screen; start on `scenePhase` `.active` after `.background` and at launch; save on `.background`; Saved screen shows kept state; `sendMessage` wake when `isReachable`.
- `mobile/ios/Runner/RelayWatchReceiver.swift`: answers the wake message; marks a watch note in its inbox JSON.
- `mobile/ios/Runner/ShortcutsInbox.swift`, `mobile/lib/shortcuts/inbox.dart`, `mobile/lib/controller.dart`, `mobile/lib/data/store.dart`, `mobile/lib/screens/timeline.dart`: a `from: watch` mark carried from the inbox into the note; no-words watch notes kept, unsent, shown as *No words heard*.
- Tests: `RelayWatchTests` for the screen state rules, `RunnerTests/ShortcutsInboxTests.swift` for the mark, Dart tests in `controller_test.dart` and `shortcuts_test.dart`.
- Docs: `mobile/README.md`, `site/src/content/docs/app/voice-notes.md`.

## Decision log

- **2026-11-11** — Asked what happens when you leave the watch app while it records → chose save it; the *X* still keeps nothing.
- **2026-11-11** — Asked whether the watch shows notes waiting for the iPhone → chose no, nothing there: the phone took the notes, so the loss is on the phone.
- **2026-11-11** — Assumed: the phone deleted the notes because it found no words, because that is the only path in the code that deletes a kept watch note without the person; the fix keeps such a note and shows it, so the next try shows the real cause.
- **2026-11-11** — Assumed: after a tap to save, the watch stays on *Saved* and a tap starts a new note, because watchOS lets no app close itself; the person leaves with the Digital Crown or by lowering the wrist.
- **2026-11-11** — Assumed: lowering the wrist for a moment does not save; only leaving the app (the system puts it in the background) saves, because a short wrist drop while talking is common.
- **2026-11-11** — Assumed: no background keep on the phone when the app is closed, because the note shows at the next open either way and it adds a second engine path to test.
- **2026-11-11** — Assumed: the watch mark is a nullable `source` column (store version 13), not a field in the note's body, because the body is the note's upload and a body field would go to the server and webhooks; the no-words state is worked out from it (a watch voice note with no words and none waiting), so it needs no second column.
- **2026-11-11** — Assumed: a no-words watch note that gets typed words while sending is on gets its upload at once, as a note kept with sending on; it is never counted as an earlier note while it has no words.
- **2026-11-11** — Assumed: a watch note whose recording is missing on the phone is kept as *No words heard* too, not deleted; and a microphone that does not start on the watch shows *Not saved*.
- **2026-11-11** — Assumed: a watch note whose inbox file has no recording at all still keeps nothing, as the review advised, because the iPhone moves the recording before it writes the inbox file, so it can't happen in normal use, and a note with nothing to play is outside this plan.
- **2026-11-11** — Assumed: the try on Matthew's own watch is a follow-up after publish, not a task, because only a publish makes the TestFlight build it needs.
- **2026-11-11** — Built: the watch records on open and saves on leave, shows *On your iPhone*, wakes the iPhone; the phone keeps a watch note with no words. Flutter checks pass here; the Swift is first compiled by CI.
- **2026-11-11** — Archived for publish: CI built the signed iPhone app with the watch app, and the watch tests passed.
