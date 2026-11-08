# A voice note records on its own full screen, and New note shows you can hold it to talk

**Status:** planned
**Branch:** wicked-termite
**Open questions:** none

## Why

While a voice note records, a small card sits low over the notes list. The list still shows behind it, so *tap anywhere to save* is easy to miss and a tap feels risky. *Cancel* looks like the main button. Also, nothing on *New note* says you can hold it to talk, so people only find voice notes by chance.

## What Changes

- **Recording fills the whole screen.** A plain screen opens over everything: a small *Listening* label with an amber dot, a large timer, and amber bars that move with your voice, so you can see the phone hears you. At the bottom it says *Tap anywhere to save*, with *Saves by itself at 5:00* under it. A round **X** at the top right keeps nothing. A voice note from Shortcuts or the Action button opens the same screen. Tap through it, light and dark, below.
  ```live
  folder: prototypes/app
  height: 940
  ```
  ```picture
  Before: pictures/before-listening.webp
  ```
  The *Before* is your screenshot from the iPhone. The *After* is the prototype above, because the phone app does not run in the plan's preview.
- **New note shows that it also records.** The round *New note* button looks as it does now. Until you make your first voice note, a short tip above the button says *Hold to talk*. When you press and hold, an amber ring fills round the button in half a second. When the ring closes, the phone buzzes and the recording screen opens. Let go early, and the page to write opens, as now.
  ```mermaid
  flowchart TD
    P["Press New note"] -->|"let go early"| W["Page to write"]
    P -->|"ring closes, 0.5 s"| R["Full-screen recording"]
    R -->|"tap anywhere"| S["Voice note saved"]
    R -->|"X"| N["Nothing kept"]
  ```
- **The website's voice note page says the same.** It describes the full-screen recording, the **X**, and the hint on *New note*.

**What stays the same:** a tap on *New note* writes; the half-second hold; the 5-minute limit; words are written on the phone; your voice never leaves the phone. The sound bars use the sound level only while you record, and keep nothing.

Non-goals: a separate mic button; a pause button; a waveform kept with the note; a change to where you land after a save (the plan *A voice note opens its own page when it saves* owns that).

## What the build needs

- **Nothing.** The sound level comes from the phone's recorder the app already uses.

## Decision log

- **2026-11-08** — Matthew asked that recording take up the whole screen, with an X at the top right to cancel and a tap anywhere to save, and that holding *New note* to talk be easier to find.
- **2026-11-08** — Asked how the app shows you can hold *New note* to talk → chose a small mic always on the button, a *Hold to talk* tip until the first voice note, and a ring that fills while you hold.
- **2026-11-08** — Asked what fills the middle of the recording screen → chose live sound bars that move with your voice, under a large timer.
- **2026-11-08** — Asked what should replace the small mic in the corner of *New note*, which looked odd → chose nothing: the button stays as it is, with the *Hold to talk* tip and the filling ring. This replaces the mic mark from the first answer.
- **2026-11-08** — Assumed: the phone's back gesture on the recording screen saves the voice note, as a tap does, because losing a recording by a swipe is worse than saving one you can delete.
- **2026-11-08** — Assumed: the *Hold to talk* tip goes for good once a first voice note starts, from a hold, Shortcuts, or the Action button, because by then the person knows how.
- **2026-11-08** — Assumed: with *Reduce motion* on, the bars still follow your voice but with no smooth easing, because they show a live fact, not decoration.
- **2026-11-08** — Assumed: the recording screen uses the paper color and Apple's thin icons, with amber as its one bright thing, by the brand rules and Matthew's phone-app look.
- **2026-11-08** — Assumed: this plan and *A voice note opens its own page when it saves* both touch the save step but do not clash: that one says where you go after a save, this one how the screen looks. Whichever lands second adapts to the first.
- **2026-11-08** — Assumed: the build first takes main (bc0ace5 or newer), because main moved the listening card to Home, changed the notes list, and changed the iPhone check, by the daily line-up note.
- **2026-11-08** — Assumed: the recording screen keeps the other plan's *open the note after a save* step, because that plan is being built now and the two must not undo each other.
- **2026-11-08** — Assumed: all sound bars follow the current level, tallest in the middle, as in the prototype the person approved, not a history of the last 17 levels, because new sound must show at once.
- **2026-11-08** — Assumed: the build went ahead on main at bc0ace5 with #72 and #73 still open, so the recording screen has no `onSaved` yet; its one `_save` method is where #73 adds it.
- **2026-11-08** — Assumed: the recording screen holds the back gesture on whichever page is on top, not through a `PopScope` in Home, because a `PopScope` in Home misses a folder page opened over it. A side swipe on the screen saves too, because the screen covers the page's own edge swipe.
- **2026-11-08** — Assumed: the hold, a save by tap and a cancel by X are a flow Claude runs by name, `voice-note.yaml`, not a tour step, because a fresh install has no speech model; the tour checks only the *Hold to talk* tip.
- **2026-11-08** — Assumed: the hold ring still fills with *Reduce motion* on, because it shows how long to hold, not decoration.
- **2026-11-08** — Assumed: after #73 merged, a save by the back gesture or a side swipe opens the new note too, as a tap does, because all three are the same save.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-voice-notes`: the recording shows on a full screen with a live sound level, an X that keeps nothing, and a tap anywhere or the back gesture that saves.
- `relay-notes-screen`: *New note* shows that a hold records: a first-time *Hold to talk* tip and a ring that fills during the hold.
- `relay-shortcuts`: *Start a voice note* opens the same full-screen recording.

## Impact

- `mobile/lib/screens/hold_to_talk.dart`: `ListeningOverlay` becomes a full-screen view; `NewNoteButton` gets the hold ring and the tip.
- `mobile/lib/screens/home.dart`: holds the overlay entry, and the back gesture's save.
- `mobile/lib/voice/recorder.dart`: `Microphone` gains a sound-level stream (`record`'s `onAmplitudeChanged`); the test fake gains one too.
- `mobile/lib/relay.dart` and the app's settings store: a kept *hold tip seen* flag.
- `mobile/test/screens_test.dart`, `mobile/test/controller_test.dart`: updated and new tests.
- `mobile/device-check/`: the tour's `new-note.yaml`, and Claude's check through `flow.sh`.
- `site/`: the voice notes and app pages.
