# Typing stays above the tool bar, Undo while you type, pinned notes, and Find in Note

**Status:** ready-to-ship
**Branch:** notes-keyboard-undo-pins
**Open questions:** none

## Why

On 2026-11-12 you typed in a long note on your iPhone and compared it with Apple Notes. Three things felt wrong. The line you type goes under the floating tool bar, so you cannot see the cursor. The tool bar floats about 20 points over the keyboard, where Apple's sits closer. And there is no Undo button while you type.

You also want two Apple Notes features: a *Pinned* part at the top of the notes list that folds, and *Pin Note* and *Find in Note* from a note's ⋯ menu.

## What Changes

- **The line you type stays in view.** When you tap into a note or type at its end, the page scrolls so the cursor stays above the tool bar, not under it. The tool bar moves down to about 6 points over the keyboard, as Apple's does.
  ```picture
  Today: pictures/today-typing.png
  After: pictures/after-typing.png
  ```
  No real picture of the keyboard: only an iPhone draws it, so a grey block stands in. The device check takes the real picture at /verify.
- **Undo shows while you type.** A round Undo button shows at the top, left of share and ⋯, after your first change. One tap takes back the last change. After an Undo, a Redo button shows beside it. Undo goes back only to when you opened the note. The keyboard stays up.
- **Pinned notes stay at the top of the notes list.** A *Pinned* part shows above *Today* when a note is pinned. A tap on *Pinned* folds it to one line, and a second tap opens it. The app keeps the fold after it closes. A pinned note shows only in *Pinned*, not also under its day. Search and the filters (*All*, *Voice*, *Photos and files*) apply to pinned notes too. A swipe right on a row pins or unpins it, as in Apple Notes.
  ```picture
  Today: pictures/today-list.png
  After: pictures/after-list.png
  Folded: pictures/after-list-folded.png
  ```
- **Pin Note and Find in Note are in a note's ⋯ menu.** *Pin Note* pins the note, and then reads *Unpin Note*. *Find in Note* puts a find bar over the keyboard: the words to find, *2 of 14*, and up and down arrows. The arrows go to each match in turn and select it, and capital letters do not matter. ✓ closes the find bar. Finding never changes the note.
  ```picture
  Today: pictures/today-menu.png
  After: pictures/after-menu.png
  Find bar: pictures/after-find.png
  ```
- **A pin follows you everywhere.** A note pinned on one phone shows in *Pinned* on your other phones and on your Relay Everything page, and a pin on the page shows on your phones. When two pin changes meet, the newer one wins. A pin is not a change to the note's words, so your webhooks get no message for it. Signed out, or with only your own webhook, the pin stays on the phone.
  ```mermaid
  flowchart TD
    P["Pin on iPhone"] --> S["Server"]
    S --> O["Other phones"]
    S --> W["Your page"]
    S -.->|no message| H["Webhooks"]
  ```
- **The guide says it.** The *Your notes* page on the website tells how to pin, fold *Pinned*, undo and find in a note.

Non-goals: no *Lock Note*, *Move*, *Duplicate* or *Scan*. No long-press menu on a row. No Find in Note on the web page, where the browser has its own find. No change to how notes send.

## What the build needs

- **Nothing.** The real keyboard and the swipe show only on an iPhone: the device check takes them at /verify, and you try them on the next TestFlight build.

## Capabilities

### New Capabilities

- `relay-note-pins`: pin and unpin a note from its ⋯ menu or a swipe; the folding *Pinned* part of the notes list; the pin synced through the server, newer change wins, with no webhook message.

### Modified Capabilities

- `relay-note-editing`: the floating tool bar sits close to the keyboard and the cursor stays above it; Undo and Redo while typing; the ⋯ menu offers *Pin Note* and *Find in Note*; the find bar.
- `relay-notes-screen`: the list starts with the folding *Pinned* part, and pinned notes leave their day groups.

## Impact

- Phone: `mobile/lib/screens/note_editor.dart` (tool bar gap, the scroll to the caret, Undo and Redo, ⋯ items, find mode), `mobile/lib/screens/note_bars.dart` (`FindBar`), `mobile/lib/screens/timeline.dart` (Pinned group, fold, swipe right), `mobile/lib/relay.dart` and `mobile/lib/controller.dart` (`Entry.pinned`, `pinNote`), `mobile/lib/data/store.dart` (three note columns and a schema step), `mobile/lib/data/api.dart` and the outbox (`PUT notes/pin`), the note pull, `mobile/lib/data/settings.dart` (the fold), and `mobile/lib/web/web_relay.dart`.
- Server: `schema/space-migrations/0018_note_pins.sql`, a new `PUT notes/pin` action, `GET notes` gives `pinned` and `pinChangedAt`, `api-doc` regenerated.
- Docs: `site/src/content/docs/app/your-notes.md`, the API page, `wiki/relay-space-migrations.md`.
- Tests: Flutter screen and store tests, server action and schema tests, a Maestro flow for pin and fold.

## Decision log

- **2026-11-12** — Asked whether a pin shows on the other phones and the web page or only on the phone that pinned it → chose everywhere, through the server.
- **2026-11-12** — Assumed: a pin sends no webhook message, because it changes how the list looks, not the note's words.
- **2026-11-12** — Assumed: Undo shows after the first change and Redo only after an Undo, both at the top left of share, because Apple Notes on iOS 26 puts Undo there.
- **2026-11-12** — Assumed: Find in Note selects the current match and does not color every match, because a color on the words would be saved into the note.
- **2026-11-12** — Assumed: a swipe right on a row also pins, because Apple Notes does it and it costs little; no long-press menu.
- **2026-11-12** — Assumed: Find in Note is phone-only; the web page keeps the browser's own find (Ctrl+F).
- **2026-11-12** — Assumed: the fold of *Pinned* stays on each phone, because it is how one screen looks.
- **2026-11-12** — Assumed: the tool bar sits 6 points over the keyboard, measured from your Apple Notes picture.
- **2026-11-12** — Assumed: the server test is `pin-note.test.ts`, not `notes-pin.test.ts`, to match `edit-note` and `delete-note`.
- **2026-11-12** — Assumed: the fold of *Pinned* reuses the folded headers the phone already keeps (`setFolded('Pinned')`, in memory on the web), not a new `pinnedFolded` setting, because a second store for folds would duplicate it.
- **2026-11-12** — Assumed: a pull drops a waiting pin older than the server's, in place of "apply only when no `note.pin` waits", because that pin would get `409` after the pull and leave the phone on the older pin.
- **2026-11-12** — Assumed: a pin made while sending was off goes when sending turns on to Relay Everything, tracked by a `pin_unsent` mark, because a pull reads only notes changed on the server; a pull still queues such a pin when it brings that note and the pin is newer.
- **2026-11-12** — Assumed: once the server takes a pin, the phone keeps the server's `pinChangedAt` from the `PUT notes/pin` answer, and a pull of a note with no unsent pin takes the server's pin and time, so a phone clock set ahead never wins over a later pin made elsewhere.
- **2026-11-12** — Assumed: a pin made on the phone is stamped at least 1 ms after the note's last known pin change, so a phone clock that runs behind never makes it look older; a pin refused as older (409) clears its `pin_unsent` mark and the next pull takes the server's pin, not a 409 answer that carries the server's pin, because the action contract sends only an error's code and message.
- **2026-11-12** — Assumed: a pin that matches the server's still saves its newer time (with no webhook message), so an older change made elsewhere still loses.
- **2026-11-12** — Assumed: a pin refused with 403 asks `GET key`, as photos do: a key that answers means a server older than pins, and the pin is dropped so the other uploads still go.
- **2026-11-12** — Assumed: a tap in the words while finding ends find mode, as in Apple Notes, not a recount of the matches.
- **2026-11-12** — Assumed: a webhook ignores `note.pin`: the outbox counts it as sent with no request.
- **2026-11-12** — Assumed: the page's bottom padding stays 120, because it is already more than the 64-point bar margin.
- **2026-11-12** — Assumed: the caret stays above the bar by the design's fallback, a post-frame scroll to the caret on each move, not `scrollBottomInset`, because flutter_quill 11.6 adds that inset over the caret's top edge too, so a caret moving up went under the top edge.
- **2026-11-12** — Assumed: *Find in Note* shows only once a voice note has its words, and *Pin Note* only on a note the phone kept.
- **2026-11-12** — Assumed: the pinned notes sort newest first by the note's time, as the day groups do, not by when they were pinned.
- **2026-11-12** — Assumed: the phone's pin tests sit in `store_test.dart` and `note_sync_test.dart` (its app group runs the controller), not `controller_test.dart` and `data_test.dart`.
- **2026-11-12** — Assumed: the step's schema test is its own file, `note-pins-schema.test.ts`, as `note-places-schema.test.ts` is, because `space-schema.test.ts` would pass the 500-line limit.
- **2026-11-12** — Assumed: the server tests ran before all phone source was written, against the build order, because the server part was finished first.
- **2026-11-12** — Built and saved: every task but the iPhone device check is done and checked; two review rounds found 8 problems, all fixed with tests (an older server's 403 on a pin, a pin made while sending was off, find after a tap, the caret moving up, phone clocks ahead or behind, a matching pin's time).
- **2026-11-12** — Assumed: the *Pinned* heading (and Home's folding names) gets a screen-reader node of its own, because the iPhone check showed its box covering the note card, so a tap on *Pinned* opened the note; fixed in the app with a test, not by moving the flow's tap.
- **2026-11-12** — Assumed: the fixed tour's settings step gets 40 seconds, not 20, to scroll to *Save*, because the second iPhone check failed there twice on a slow Mac with *Save* on the screen (each screen read took about 10 seconds); the app's Settings did not change.
- **2026-11-12** — Assumed: the find field draws no outline or fill, because the iPhone picture showed the app's green field box inside the find pill, which Apple Notes does not have.
- **2026-11-12** — Asked whether to fix the settings step again or publish anyway after the third iPhone check failed there → chose to fix it and check again: its scroll waits at most 500 ms for the screen to settle, because the address field's blinking cursor never settles; the 40-second time limit stays.
- **2026-11-12** — Asked whether to publish after the fourth iPhone check failed at the fixed Settings step (a slow Mac's 1-second tap on the gear counted as a long press), with the change's own pin step passed in three checks → chose to publish anyway; Claude's scenario check on the iPhone never ran.
- **2026-11-12** — Archived for publishing: specs merged into `openspec/specs/` (`relay-note-pins` new; `relay-note-editing` and `relay-notes-screen` updated).
