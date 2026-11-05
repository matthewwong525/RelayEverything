# Talk a note into your phone

**Status:** ready-to-ship
**Branch:** nifty-gecko
**Open questions:** none

## Why

Typing a note takes both hands and your eyes. Talking takes a few seconds. Today only the Pebble ring takes voice notes, and Pebble's app writes their words. Now you can hold a button in the Relay app, talk, and let go: the phone writes the words itself. Your voice never leaves the phone, and the words cost nothing to make.

## What Changes

- **Hold to talk.** A microphone button sits beside *New note*. Hold it, talk, and let go. The note shows at once, and its words fill in a few seconds later. This works with no signal and no server.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">On this phone</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Voice</span><span class="muted">9:42</span></span><span class="muted">Writing the words…</span><span class="bar"/></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Voice</span><span class="muted">9:41 · 0:12</span><span class="grow"/><button class="btn-ghost">Play</button></span><span>Ask the fab if the flex stiffener can be 0.2 mm</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Typed</span><span class="muted">8:15</span></span><span>Order more TL3312 switches</span></div>
    <div class="row gap"><span class="grow"/><button class="btn-ghost">Hold to talk</button><button class="btn-primary">New note</button></div>
  </div>
  ```
  The phone app is Flutter, which the review page can't run, so its screens are sketches.
- **While you hold.** The button shows that the phone is listening and for how long. Let go to save. Slide your finger off the button to throw the note away.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">On this phone</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Typed</span><span class="muted">8:15</span></span><span>Order more TL3312 switches</span></div>
    <div class="card col gap"><span class="row gap"><span class="tag">Listening</span><span class="muted">0:07</span></span><span class="muted">Let go to save. Slide off to cancel.</span></div>
  </div>
  ```
- **The first time, the phone gets its speech model.** Voice notes need a 57 MB file, one time. The app asks before it gets it, so nothing downloads by surprise. Typed notes never need it.
  ```screen
  <div class="card col gap phone">
    <h3>Get the speech model?</h3>
    <span class="muted">Voice notes need a 57 MB file, one time. The phone uses it to write your words. Your voice never leaves this phone.</span>
    <div class="row gap"><span class="grow"/><button class="btn-ghost">Not now</button><button class="btn-primary">Get it</button></div>
  </div>
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">On this phone</span></div>
    <div class="card col gap"><span>Getting the speech model… 40%</span><span class="bar"/><span class="muted">You can type notes now. Voice notes start when it is done.</span></div>
  </div>
  ```
- **No speech, no note.** A press shorter than half a second, or a recording with no words in it, saves nothing. A bump in your pocket makes no empty note.
  ```mermaid
  flowchart TD
    A["Let go"] --> B{"Held 0.5 s or more?"}
    B -->|"no"| X["Nothing saved"]
    B -->|"yes"| C["Phone writes the words"]
    C --> D{"Any words?"}
    D -->|"no"| Y["Nothing saved: No speech heard"]
    D -->|"yes"| E["Note with its words"]
  ```
- **The recording stays on your phone.** You can play it back to check a word. With sending on, only the words go to your Relay server, the same as a typed note. The recording never leaves the phone.
  ```mermaid
  flowchart TD
    A["Your voice"] --> B["Recording on this phone"]
    B --> C["Words, written here"]
    C --> D{"Sending on?"}
    D -->|"no"| E["Stays on this phone"]
    D -->|"yes"| F["Words go to your Relay server"]
  ```
- **Settings shows the speech model.** You see its size and can remove it to free space. The next voice note asks to get it again.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><span class="grow">Pin notes to where I am</span><span class="tag-outline">Off</span></div>
    <div class="sep"/>
    <span>Voice notes</span>
    <div class="row gap"><span class="grow muted">Speech model: on this phone, 57 MB</span><button class="btn-ghost">Remove</button></div>
    <span class="muted">Your voice is written into words on this phone. Recordings never leave it.</span>
    <div class="sep"/>
    <div class="row gap"><span class="grow">Send to your Relay server</span><span class="tag-outline">Off</span></div>
  </div>
  ```
- **The Relay website tells how.** A new *Voice notes* page, and the *Notes*, *Settings* and *Privacy* pages say where your voice goes: nowhere but your phone.

Non-goals: speech to text on a server or in the cloud (a later change, maybe for paid users); words for Pebble ring notes, which Pebble's app writes; sending recordings to your server; changing a note's words after it is saved; languages other than English.

## What the build needs

- **The offline-by-default change on the main copy**: Ready. Its chat is publishing it now, and the orchestrator chat starts this build after it is in.
- **Your iPhone**: Ready, for the last check. That check needs TestFlight, which waits for Apple to finish your membership; the build and its tests go on before then.

## Capabilities

### New Capabilities
- `relay-voice-notes`: the phone app records a voice note while the person holds a button, writes its words on the phone with a downloaded speech model, keeps no note without speech, keeps the recording only on the phone, and sends only the words when sending is on.

### Modified Capabilities
- `relay-sending` (from `relay-offline-by-default`, on `main` before this build starts): *The app works offline by default* allows one more network request with sending off: the speech-model download the person agreed to.

## Impact

- Changed: `mobile/` (new `lib/voice/` for recording, the model and transcription; timeline, settings and store; `pubspec.yaml`; iOS `Info.plist` and Android manifest for the microphone; tests), `mobile/README.md`.
- New dependencies: a Flutter binding of whisper.cpp, a recorder and a player package.
- Website: new `site/src/content/docs/app/voice-notes.md` and its menu entry in `site/sidebar.mjs`; `app/your-notes.md`, `app/settings.md`, `privacy.md`.
- No server route, table or migration changes. A voice note reaches the server as a typed note's words.
- The Android build compiles whisper.cpp, so the phone build on GitHub takes longer.

## Decision log

- **2026-11-05** — Asked in a WongOS chat where speech becomes words → chose on the phone only, with no cloud for now, to keep cost at zero and voice private; cloud may come later for paid users.
- **2026-11-05** — Asked which voice notes the phone turns into words first → chose talking into the phone in the Relay app; the same engine can serve the Relay ring later.
- **2026-11-05** — Assumed: the phone gets the speech model at the first voice note, after the person agrees, not at first open, because the offline-by-default change promises no network use until sending is on. The orchestrator chat, for Matthew, said to take the recommended option.
- **2026-11-05** — Assumed: the recording stays on the phone for playback and only the words are sent, because Matthew chose on-device to keep voice private and it needs no server change. The orchestrator chat said to take the recommended option.
- **2026-11-05** — Assumed: the English-only Whisper base model, because it is more correct for English at the same size. The orchestrator chat said to take the recommended option.
- **2026-11-05** — Assumed: the model is `ggml-base.en-q5_1` (about 57 MB), because it is the smallest model that writes everyday speech well; `tiny.en` makes more mistakes and `small.en` is 3 times larger.
- **2026-11-05** — Assumed: the model downloads from whisper.cpp's own Hugging Face page, checked against a fixed SHA-256, because Relay's site can not serve a 57 MB file and the phone may have no Relay server. The Privacy page says so.
- **2026-11-05** — Assumed: hold to talk, with slide-off to cancel, because it mirrors the Relay ring and the 0.5 s rule stops pocket presses.
- **2026-11-05** — Assumed: a voice note goes to the server as a typed note's words, with no new source, because a server change is not needed for the first version and the phone shows *Voice* from its own record.
- **2026-11-05** — Assumed: a note whose words are not written yet waits on the phone and goes to the server only when it has words, because an empty note on the server would break "no speech, no note".
- **2026-11-05** — Assumed: Settings shows the model with a *Remove* button, because 57 MB is large on a full phone.
- **2026-11-05** — Assumed: the plan is written now and built only after `relay-offline-by-default` is on `main`, because the orchestrator chat said so and that change rewrites the same screens.
- **2026-11-05** — Assumed: the binding is `whisper_cpp_flutter_plus` 0.5.1 (whisper.cpp 1.9.2, iOS 14+, Android API 24+), with `record` 7.1.2, `just_audio` 0.10.6, `path_provider` 2.1.6 and `crypto` 3.0.8, each checked on pub.dev for iOS 15 and Android minSdk 26. The binding runs the model in its own background isolate, so the app needs no isolate of its own. The binding's voice-activity check needs a second model download, so the app uses the word cleaning alone.
- **2026-11-05** — Assumed: the Android debug build and its build-time cost are checked by GitHub Actions on the pull request, not on this computer, because this computer has no NDK and under 5 GB free. The orchestrator chat said the pull request's Android build counts for task 1.1 and 3.4. `mobile-android.yml` now caches Gradle.
- **2026-11-05** — Assumed: the model URL names the fixed whisper.cpp revision `5359861c…` in place of `main`, with SHA-256 `4baf70dd…2fdd2f` and 59,721,011 bytes read from Hugging Face's file record, because a fixed revision never changes under the checksum.
- **2026-11-05** — Assumed: the model is kept out of iCloud by a small `relay/files` channel in `AppDelegate.swift`, and out of Android backup by `backup_rules.xml` and `data_extraction_rules.xml`, because Android's 25 MB backup limit would stop the whole backup. The Swift code is not compiled here: the iPhone build waits on the App Store Connect secrets.
- **2026-11-05** — Assumed: the store keeps a recording's path from the support folder (`voice/<clientId>.wav`), not the full path, because the iPhone app's folder path changes when the app updates.
- **2026-11-05** — Assumed: voice notes are not pinned to a place, because Settings says *Each typed note keeps where you were*; pinning a voice note can come later.
- **2026-11-05** — Assumed: a press shorter than 0.5 s shows *Hold the button while you talk, then let go.*, so a tap is not a silent no-op; a silent recording shows *No speech heard. Nothing was saved.*
- **2026-11-05** — Assumed: recordings with no note, left when the app closed during a hold, are deleted at the next open, and a note whose words fail stays waiting and is tried again at the next open.
- **2026-11-05** — Assumed: recordings are kept out of phone backups, so they are lost when moving to a new phone, because the docs promise a recording never leaves the phone and a large backup would stop Android's whole backup.
- **2026-11-05** — Assumed: task 5.2's phone check waits on Matthew's iPhone through TestFlight and does not block the ship, because the orchestrator chat, for Matthew, said device-only steps go to an open thread. The thread is in memory.
- **2026-11-05** — Check: `.github/workflows/mobile-android.yml` adds a Gradle cache to the Java setup; no check is turned off or weakened, because whisper.cpp now compiles with the NDK on each Android build and the cache keeps that time down.
- **2026-11-05** — Assumed: the build and its review are done and saved for the pull request's checks, because the Android build, the staging site check and the publish run there; the iPhone check waits on TestFlight.
- **2026-11-05** — Assumed: the pull request's Android build is the build check for tasks 1.1, 3.4 and 5.2: it passed in 9 min 7 s, against 7 min 35 s and 13 min 19 s for the last two builds on `main`, so whisper.cpp adds little; it made the `.apk` file (40 MB zipped). The site preview at commit f304b9c printed `result=deployed` and shows the *Voice notes* page.
- **2026-11-05** — Assumed: archived for publishing with every task ticked; the iPhone check through TestFlight stays an open thread, because the orchestrator chat, for Matthew, said device-only steps do not block the ship.
