# Proposal: Voice notes get their words on the iPhone

**Status:** ready-to-ship
**Branch:** repo-status-next-steps
**Open questions:** none

## Why

On the iPhone test build, a voice note never gets its words. Matthew held the button for 3 seconds, and the note still showed *Writing the words…* after more than 5 minutes, with no message. Two faults can cause it: the step that reads the recording can fail in a way the app does not catch, and the iPhone build can leave out the speech parts that the app looks up when it runs.

## What Changes

**What you get**

- **A voice note gets its words in a few seconds.** The app reads the recording in a way that cannot fail like this, and the iPhone build keeps every speech part that the app looks up.
  ```mermaid
  flowchart LR
    H[Hold and talk] --> N[Note shows at once]
    N --> W[Words in a few seconds]
  ```
- **A note never stays on *Writing the words…* for ever.** When the words fail, or take longer than the time limit, the note keeps its recording and says so. A **Try again** button writes the words again, and the next app open tries again too.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><span class="tag">Voice</span><span class="grow"/><button class="btn-ghost">Play</button></div>
    <div class="muted">The words did not come. Your recording is safe.</div>
    <div class="row gap"><button class="btn-primary">Try again</button></div>
    <div class="muted">2:14 PM · 0:03</div>
  </div>
  ```
- **The iPhone build stops if a speech part is missing.** The build checks for the speech parts before it goes to TestFlight, so a build with this fault never reaches your phone.
  ```mermaid
  flowchart LR
    B[iPhone build] --> C{Speech parts there?}
    C -- yes --> T[TestFlight]
    C -- no --> S[Build stops]
  ```

**What changes in how you work**

- **Install the next test build from TestFlight.** It comes on its own after this change is published.
- **The setup notes say the App Store Connect key needs Admin access.** An App Manager key cannot sign the iPhone build in the cloud, as the first build showed.

**What of yours stays**

- **The note you recorded stays.** Its recording is kept, and the new build writes its words when you open the app.
- **Voice stays on the phone.** The words are still written on the phone, with no signal and no server.

**What is left out, and why**

- **No new speech engine.** The fault is in how the app calls the engine, not in the engine.
- **No test that runs on a real iPhone in the build.** The build has no phone to run on. The symbol check and the phone tests cover the two faults, and you check one note on your phone.

**What you do yourself**

- **Record one short voice note on the new build** and see the words fill in.

## What the build needs

- **The App Store Connect key with Admin access**: Ready. It is in the repository's secrets and in this computer's private settings file.
- **The speech model on your phone**: Ready. You downloaded it on build 2.

## Decision log

- **2026-11-06** — Assumed: fix both possible causes in one change, because the phone build is the only place the fault shows, and each test build takes about 20 minutes.
- **2026-11-06** — Assumed: the time limit is 2 minutes, or the recording's length if longer, because a 5-minute note can take near a minute to write on an older phone.
- **2026-11-06** — Assumed: a failed note shows a **Try again** button, not only a message, because Matthew waited with no way to act.
- **2026-11-06** — Assumed: the Admin-access fix to the setup notes goes in this change, because it is a small doc fix found in the same TestFlight work.
- **2026-11-06** — Matthew parked this plan before the build: the project moves to Durable Objects first, and this plan may come back later. Check it against that work before you build it.
- **2026-11-07** — Assumed: the plan still fits main after the spaces work and 23 other changes: the voice code, the speech package (0.5.1) and the iOS build are as the plan found them. Two tasks change: the setup-notes fix now touches only `.env.example`, because `mobile/README.md` no longer names the key's access and the wiki already says Admin; and the link flags go beside the flags Runner now has.
- **2026-11-07** — Assumed: the iPhone build keeps global symbols (Strip Style Non-Global) and the speech-parts check reads the `.ipa` sent to TestFlight, because an archive's default strip removes the symbols the app looks up, which `-u` cannot stop.
- **2026-11-07** — Check: `mobile/ios/fastlane/Fastfile` gets a new step that stops the iPhone build when the archive lacks a speech part, because a build with that fault must not reach TestFlight. It loosens nothing: it adds a check.
- **2026-11-07** — Built and saved; local checks pass. Left: the first iOS build with the new check, then one voice note on Matthew's phone. Matthew asked whether whisper.cpp is the best speech engine: research says keep it and fix it, because it is small (57 MB) and works fully offline; the next choice is `sherpa_onnx` with Moonshine or Parakeet, after the app is timed on a real iPhone.
- **2026-11-07** — Asked: publish now or after the phone test → Matthew chose publish now. The iPhone build passed its speech-parts check and is on TestFlight; his voice-note test on the phone comes after publish.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-voice-notes`: a voice note whose words fail or pass the time limit shows a message and a **Try again** button, keeps its recording, and tries again at the next open.

## Impact

- `mobile/lib/voice/transcriber.dart`: read the WAV in a top-level function given only the path.
- `mobile/lib/controller.dart`: `_write` catches every error and has a time limit; a failed set in memory; a retry action.
- `mobile/lib/relay.dart`, `mobile/lib/screens/timeline.dart`: the failed state and the **Try again** button.
- `mobile/ios/Runner.xcodeproj/project.pbxproj`: keep each looked-up `wf_*` symbol linked in Release.
- `mobile/ios/fastlane/Fastfile`: a symbol check on the `.ipa` before TestFlight.
- `mobile/test/`: tests for an Error, a time-out, and the retry.
- `.env.example`: App Store Connect key access is Admin.
- `site/src/content/docs/app/voice-notes.md`: the failed state and **Try again**.
