# Proposal: A voice note opens its own page when it saves

**Status:** ready-to-ship
**Branch:** voice-note-opens-note
**Open questions:** none

## Why

When you tap to save a voice note, the listening card closes and you stay on the page you were on. You then have to find the new note in the list to see its words come in. The note you just made is the one you want to see.

## What Changes

**What you get**

- **A tap to save opens the new note.** The listening card closes, and the note's page opens at once. You see *Writing the words…*, then the words fill in on that page. The back button takes you to the page you were on before.
  ```mermaid
  flowchart TD
    T[Tap to save] --> P[Note's page opens]
    P --> W[Words fill in]
    P --> B[Back: page before]
  ```
  This changes where you land, not how a screen looks, so the plan shows the flow and no screenshot.
- **The same from Shortcuts and the Action button.** A voice note started there also opens its page when you tap to save, over any page that was open.
- **A silent recording goes back by itself.** When the phone hears no speech, it keeps no note, as now. The page closes, and the list says *No speech heard. Nothing was saved.*
  ```mermaid
  flowchart TD
    P[Note's page opens] --> Q{Speech?}
    Q -- yes --> W[Words fill in]
    Q -- no --> L[Back to list, with message]
  ```

**What stays the same**

- **Cancel keeps nothing and opens nothing.**
- **A recording too short to keep, or one the phone could not save,** shows its message and opens no page.
- **A short tap on New note** still opens the page to write a note.

**What is left out, and why**

- **A recording that stops itself at 5 minutes does not open its page.** You may have put the phone down. The note shows at the top of the list, as now.

## What the build needs

- **Nothing.**

## Decision log

- **2026-11-08** — Matthew asked that a voice note open its page after it saves, instead of staying on the current page.
- **2026-11-08** — Assumed: a voice note started from Shortcuts or the Action button opens its page too, because it uses the same listening card and the same tap to save.
- **2026-11-08** — Assumed: when the phone hears no speech, the open page goes back by itself, because the note no longer exists and the page must not show an empty note.
- **2026-11-08** — Assumed: a note page whose note is gone from the phone always goes back, not only after a voice note, because a page for a note that does not exist helps no one. It also suits the later *Delete a note everywhere* work.
- **2026-11-08** — Assumed: a recording that stops at the 5-minute limit does not open its page, because nobody tapped and the person may not be looking.
- **2026-11-08** — Assumed: the plan moves to `main` as it is now, because the build found the note page is now `NoteEditor` and the listening card is shown by `home.dart`. What you see does not change.
- **2026-11-08** — Assumed: no prototype picture, because the change is where the app goes after a save, and the note page itself does not change.
- **2026-11-08** — Assumed: the app finds the saved note by its time to the millisecond, because the phone keeps a note's time to the millisecond, so an exact match would never find it on a real phone.
- **2026-11-08** — Assumed: the note's back button says *Home* when Home is under it, and *Back* over any other page, because the button must name the page it goes back to.
- **2026-11-08** — Assumed: the note's page starts from the note as the phone has it when the page opens, and closes at once if the note is already gone, because the words, or the *No speech* result, can come between the tap and the page.
- **2026-11-08** — Assumed: the spec drops the *Deleted on another phone* scenario, because a sync never removes the note that is open on its page; that note goes at the first sync after the page closes. A change to that hold is outside this plan.
- **2026-11-08** — Built and saved inside `/ship`; 482 phone tests pass. The second look found that a page opened over another note gave up that note's sync hold, and that *New note* inside a note kept a closed note held; both are fixed and tested.
- **2026-11-08** — Archive checkpoint inside `/ship`. The first save's wait lost its GitHub connection (TLS handshake timeout); `gh pr checks 73` then showed every check passing, both phone builds included, so task 3.2 is ticked.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-voice-notes`: a tap to save a voice note opens the new note's page.
- `relay-note-deleting`: an open note's page closes when its note is gone from the phone.

## Impact

- `mobile/lib/screens/hold_to_talk.dart`: `ListeningOverlay` takes an `onSaved(DateTime at)` callback and calls it after a save with no problem.
- `mobile/lib/screens/home.dart`: `_showListening` passes `onSaved`, which finds the voice entry with that time and opens `NoteEditor` with `openPage`.
- `mobile/lib/screens/note_editor.dart`: `NoteEditor` pops when its kept note is no longer in `relay.entries`.
- `mobile/test/screens_test.dart`: tests for the open, the silent recording, Cancel, and the gone note.
- `site/src/content/docs/app/voice-notes.md`: the tap to save opens the note.
