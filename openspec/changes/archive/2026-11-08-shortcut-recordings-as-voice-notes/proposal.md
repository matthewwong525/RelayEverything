# Proposal: A recording from Shortcuts becomes a voice note

**Status:** shipped
**Branch:** add-audio-recording-to-note
**Open questions:** none

## Why

Matthew has a shortcut that records audio and sends it by email with a note. He wants the same with Relay Everything: record, then give the recording to **Add a note**. Today the action keeps the recording only as a plain file, and its **Files** slot hides behind a small arrow, so the recording gets no words and is hard to find.

## What Changes

**What you get**

- **A recording you give to *Add a note* becomes a voice note.** Use **Record audio** in Shortcuts, then **Add a note** with the **Recorded Audio**. The note shows at once as a voice note. The phone writes its words, as when you hold **New note**, and the note has **Play**. If the words fail, the note keeps the recording and shows **Try again**.
  ```mermaid
  flowchart LR
    R[Record] --> A[Add a note]
    A --> N[Voice note]
    N --> W[Words]
  ```
- **Words you type go first.** Give *Add a note* words and a recording, such as *Note @ 7:07 PM*, and the note starts with your words. The written words of the recording follow on the next line. With no speech in the recording, the note keeps your words and the recording.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><span class="tag">Voice</span><span class="grow"/><button class="btn-ghost">Play</button></div>
    <div>Note @ 7:07 PM</div>
    <div>Call the plumber about the kitchen tap before Friday.</div>
    <div class="muted">7:07 PM · 0:12</div>
  </div>
  ```
- **The *Files* slot shows in the action's line.** The action reads *Add Words with Files to Relay Everything*, as Mail reads *Send Recorded Audio with Note*. You no longer open the arrow to find it.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><span class="tag-outline">Relay Everything</span></div>
    <div>Add <span class="tag">Note @ Current Date</span> with <span class="tag">Recorded Audio</span> to Relay Everything</div>
  </div>
  ```
  This is a sketch: the action's line is drawn by Apple's Shortcuts app, which no prototype can run.

**What of yours stays**

- **Other files stay files.** A photo, a PDF, or a recording given together with other files is kept as a file, as today.
- **Your voice stays on the phone.** The phone writes the words itself, with no server. With *Send my notes* off, the app makes no network call. With it on, the note goes to your space once its words are written, as a voice note does today.
- **A recording the phone cannot read stays a file.** The note keeps it as a plain file, so nothing is lost.

**What is left out, and why**

- **No new note type.** A voice note already holds a recording, its words, **Play** and **Try again**.
- **No words in the background while the app is closed.** The speech engine runs only in the open app. When the app is closed, the note waits, and its words are written the next time you open the app.

**What you do yourself**

- **Install the next test build from TestFlight**, then run your *Record audio* shortcut with **Add a note** in place of **Send**.

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-08** — Asked: keep a passed-in recording as a plain file with the *Files* slot shown in the line, or make it a voice note → the person ran `/ship` with no pick; under `/ship` the recommendation was taken: make it a voice note, and show *Files* in the line too.
- **2026-11-08** — Assumed: a recording becomes a voice note only when it is the only file given, because a note with a recording and other files has no voice-note shape today.
- **2026-11-08** — Assumed: typed words go first and the written words follow on the next line, because Matthew's shortcut sends a label (*Note @ Current Date*) with each recording.
- **2026-11-08** — Assumed: with no speech, a note with typed words keeps the words and the recording; a note without typed words is dropped and says it heard no speech, as a held voice note does.
- **2026-11-08** — Assumed: the iPhone side turns the recording into the 16 kHz WAV the speech engine reads, because Shortcuts gives `.m4a` and Apple's own audio tools read every format Shortcuts makes.
- **2026-11-08** — Assumed: the 25 MB file limit applies to a recording too, so one rule covers every file the action takes.
- **2026-11-08** — Assumed (build): Swift writes the WAV into the note's inbox folder, `shortcuts-inbox/<id>/voice.wav`, and the app moves it to `voice/<id>.wav` only after it keeps the note, because the app's sweep for stray recordings, which runs as it opens, deleted a WAV written to `voice/` before its note was kept.
- **2026-11-08** — Assumed (build): the note page shows a voice note's typed words above *Writing the words…* or *Try again*, because a shortcut's label is the only words the note has until its own words are written, and a page with no words looks empty.

- **2026-11-08** — Built and reviewed; local checks pass (287 phone tests). The second look found a Swift compile error and a weak sweep test, both fixed, then nothing. Left: the iPhone CI build compiles the Swift change, then Matthew runs his *Record audio* shortcut on the TestFlight build.

- **2026-11-08** — Archive checkpoint: all checks passed on PR #55, including the iPhone TestFlight build, so the Swift change compiles. Left after publish: Matthew runs his *Record audio* shortcut on the new TestFlight build.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-shortcuts`: *Add a note* turns a lone recording into a voice note, with typed words first.

## Impact

- `mobile/ios/Runner/RelayIntents.swift`: the parameter summary shows *Files*; a lone audio file is turned into a 16 kHz WAV in the note's inbox folder and sent as `recording`; the app moves it to `voice/<id>.wav` once the note is kept.
- `mobile/lib/shortcuts/bridge.dart`, `mobile/lib/shortcuts/inbox.dart`, `mobile/lib/controller.dart`, `mobile/lib/data/store.dart`: keep a shortcut recording as a pending voice note with typed words.
- `mobile/lib/screens/note.dart`: a voice note's typed words show above *Writing the words…* and *Try again*.
- `site/src/content/docs/app/shortcuts.md` and `voice-notes.md`: the new behavior and a recipe.
