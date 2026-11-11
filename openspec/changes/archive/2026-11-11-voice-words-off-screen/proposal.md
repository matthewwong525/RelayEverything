# Voice notes get their words when the app is not on screen, and one failed note does not stop the next

**Status:** ready-to-ship
**Branch:** fix-missing-words-output
**Open questions:** none

## Why

On 2026-11-11, three voice notes in a row showed *The words did not come*, each less than a minute after it was saved. The first note of that minute had its words.

The likely cause is in how the iPhone writes the words. The speech engine uses the phone's graphics chip. An iPhone refuses graphics work from an app that is not on the screen. Since the watch update of 2026-11-11, a watch note starts the iPhone app out of sight, and the app writes the words there. That write fails at once.

Then a second fault makes it *a bunch*. After one failed write, the speech engine stays in an error state until the app is fully closed. The app keeps the same engine, so each later note fails too, also a note made on the phone, and also **Try again**.

The code shows both faults. No record from your phone proves that the first failure was the graphics chip, because the app keeps no reason for a failure. This plan also fixes that.

## What Changes

- **The iPhone writes the words the same way on screen and off screen.** It uses the phone's processor, not the graphics chip. The processor works when the app is out of sight, when the phone is locked, and when you leave the app while the words are written. A short note may take one or two seconds longer to show its words.
  ```mermaid
  flowchart TD
    N["Note saved, app off screen"] -->|Today| G["Graphics chip refused"] --> F["The words did not come"]
    N -->|After| C["Processor writes"] --> W["Words fill in, note sends"]
  ```
- **One failed note does not stop the next.** After a failed write, the app lets the speech engine go and loads a new one for the next note. Today the broken engine stays until you close the app.
  ```mermaid
  flowchart TD
    A["Note 1 fails"] -->|Today| B["Same engine: note 2, 3, 4 fail"]
    A -->|After| D["New engine: note 2 gets its words"]
  ```
- **A failed note tries again by itself when you come back to the app.** Today it waits for **Try again**, or for the app to close and open. The notes that failed today get their words the first time the updated app opens.
- **The iPhone gets time to finish a watch note in your pocket.** When the watch hands a note over, the app asks the iPhone for time to write the words and send the note, about 30 seconds. If the iPhone stops the app first, the note finishes the next time the app runs.
- **A failed note says why.** Under *The words did not come. Your recording is safe.*, a small line gives the reason, such as *Why: the speech engine stopped (code -6).* or *Why: the phone took more than 2 minutes.* The next time a note fails, the reason is on the phone, not lost.
  ```picture
  Today: pictures/today-failed-note.png
  After: pictures/after-failed-note.png
  ```
- **The guide and the wiki say it.** The voice notes page of the website gets the *Why* line and the try on return. The wiki keeps the lesson: an iPhone refuses graphics work from an app that is off screen, and a speech engine that failed once must be made again.

Non-goals: no change to the watch app, to Android's speech engine, to the speech model, or to the time limit. No new button and no new setting.

## What the build needs

- **Your iPhone, your Apple Watch and the next TestFlight build**: Ready. After publish, lock the phone, record three short notes on the watch, then open the phone app. Each note must have its words. This is the only real proof: no test on this computer has a microphone, a watch or a real iPhone.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-voice-notes`: the words are written when the app is not on the screen; one failed write does not fail the next note; a failed note tries again on return to the app and gives its reason.

## Impact

- `mobile/lib/voice/transcriber.dart`: `whisperConfig` gives `WhisperBackend.cpu` on iOS; `WhisperTranscriber.write` disposes and drops its engine when a run fails, so the next run loads a new one.
- `mobile/lib/controller.dart`: `_write` keeps a failed note's reason; `resume` writes failed notes again; `Entry` gets the reason.
- `mobile/lib/relay.dart`, `mobile/lib/screens/note_editor.dart`: the *Why* line on a failed note's page.
- `mobile/lib/shortcuts/bridge.dart`, `mobile/ios/Runner/RelayIntents.swift`, `mobile/ios/Runner/RelayWatchReceiver.swift`: `inboxChanged` answers when the note's words are written and sent, and Swift holds a background task until then.
- `mobile/test/voice_test.dart`, `controller_test.dart`, `screens_test.dart`, `shortcuts_test.dart`: tests for each rule.
- `site/src/content/docs/app/voice-notes.md`, `mobile/README.md`, `wiki/relay-watch.md`: the guide and the lesson.

## Decision log

- **2026-11-11** — Assumed: the first failure was the graphics chip refused off screen, because the failures came in under a minute (not the 2-minute limit), began after the update that starts the app out of sight for a watch note, and the engine's code keeps an error state after one failed graphics run. No record from the phone proves it; the *Why* line is in the plan so the next failure does.
- **2026-11-11** — Assumed: the iPhone always uses the processor, not the graphics chip on screen and the processor off screen, because one way has no switch to get wrong and a note that is half written when you lock the phone then also finishes. The cost is speed: the speech model is the small 57 MB one, so a short note takes about one or two seconds more. This is an estimate, not a measurement on your phone.
- **2026-11-11** — Assumed: Android does not change, because Android has no such rule and no failure is known there.
- **2026-11-11** — Assumed: a failed write is not tried a second time at once, only on return to the app, at the next open, or by **Try again**, because a new engine for the next note and the try on return already recover it, and a loop of tries on a recording that can't be read helps nobody.
- **2026-11-11** — Assumed: the reason is a small grey line on the failed note's page only, not in the list and not in the notice, because you see it only when you look at a note that failed. The reason stays on the phone and is not sent.
- **2026-11-11** — Assumed: the app asks the iPhone for time only for a watch note's hand-off, because a note made on the phone already starts on screen, and the iPhone gives an app a short time to finish when you leave it.
- **2026-11-11** — Assumed: the CI check and the watch test are not build tasks, because `/ship` waits for CI before it publishes, and the watch test needs the TestFlight build that only the publish makes; the watch test stays in *What the build needs*.
- **2026-11-11** — Assumed: the build goes on top of the new notes list and voice player (#114), published after this plan was drawn, because the fix does not touch the player; the *After* picture may show the old Play line.
- **2026-11-11** — Assumed: when a watch note wakes the app and the app is not ready yet, the iPhone keeps the time it asked for until the app is ready and the words are written, not only until the note is in the inbox, because a wake from the watch is the case that needs the time; iOS's own limit of about 30 seconds still ends it. The design said it ends at once in that case.
- **2026-11-11** — Assumed: the *Why* line uses the page's small grey style, as the date above it does, and a time limit under 1 minute, which only a test uses, is given in seconds.
- **2026-11-11** — Assumed: the notice *The words did not come* shows only the first time each note fails, as long as the app runs, because the try on each return to the app would show it again for the same note each time. A different note that fails later shows it once. Several notes that fail together still show it once. A note that fails again after **Try again** shows no notice; its page still shows the failed state and the *Why* line.
- **2026-11-11** — Assumed: the iPhone's speech engine sits behind a small interface that a test can replace, because the package's engine is a final class that a test can not fake. The app loads the same engine, with the same settings, as before. A test now proves that a failed run lets its engine go and that a run stopped at the time limit keeps it.
- **2026-11-11** — Archived for publish: the full phone app test run passed (765 tests) and `flutter analyze` found no issues; the Swift is first compiled by CI, and the watch test waits for the TestFlight build.
