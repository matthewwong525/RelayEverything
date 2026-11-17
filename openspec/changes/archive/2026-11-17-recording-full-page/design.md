## Context

`RecordingCard` in `mobile/lib/screens/note_blocks.dart` folds its transcript in place. The open, editable state is a `TextField` with `InputDecoration.collapsed`. `collapsed` sets only `border`, so the theme's `enabledBorder` and `focusedBorder` from `mobile/lib/brand.dart` still draw: that is the rounded box in Matthew's screenshot. The *Transcript* header is an `InkWell`, so a tap spreads the Material splash over the card. The same card shows on the phone, on the web page and in the Mac app.

## Goals / Non-Goals

**Goals:** a recording opens on its own page, as in Apple Notes; the words show as plain text with no box; no tap shows a splash.

**Non-Goals:** no change to the player, recording, speech, sync or data. No words highlight as they play.

## Decisions

- **A new `RecordingPage`, pushed with the nearest `Navigator`.** It holds the words, copy, editing and a `VoicePlayer` at the bottom. In the wide layout this covers the note's pane, as other pages from the note do. Alternative, a bottom sheet: it hides the way back and is not what Apple Notes does.
- **The editable words use `InputDecoration.collapsed` plus `enabledBorder`, `focusedBorder` and `disabledBorder` set to `InputBorder.none`,** so the theme draws nothing. The words read as page text: 17 px, line height 1.5, ink.
- **The *Transcript* row uses a `GestureDetector` with an opaque hit area, not `InkWell`.** No ripple, no grey shade; the page opening is the feedback.
- **The card only holds status.** *Writing the words…*, the failed line with *Try again*, and *No words heard* stay in the card, as now. Only a recording with words gets the row and the page.
- **The kept-on-blur logic moves to the page.** The page keeps the words when the field loses focus, when the check button closes the keyboard, and when the page closes. `didUpdateWidget` still takes newer words from sync while the field has no focus.
- **Copy sits in the page's top bar** as a `RoundIconButton` with `CupertinoIcons.doc_on_doc`, tooltip *Copy transcript*, showing no message, as now.

## UX

### Use-case brief

Matthew records a voice note, then reads, copies or fixes its words. Common case: read the words of a short note. Edge cases: a long transcript (scrolls), a wrong word (fix it on the page), a note from another phone (read-only words), words still writing or failed (the card says so, and there is no page yet).

### Flow

Note → tap *Transcript ›* → the recording's page → read, play, copy or fix → back to the note.

### Hierarchy

The note page's primary action stays writing. On the recording's page, the words lead; the player sits at the bottom, in reach of the thumb.

### Review

[review.html](review.html): the What Changes items show the card in the note, the recording's page, and fixing a word.

### Components

Existing: `VoicePlayer`, `BackTo`, `RoundIconButton`, `Card`, brand colors. New: `RecordingPage`, because a recording had no page of its own.

## Risks / Trade-offs

- A transcript fix now takes one more tap → it is a rare action, and the page gives the words room.
- The device check opened the transcript in place → its flow taps the row and checks the page.
- The chat *Also am i not allowed adding text after media* changes where a card sits in the note's words → this plan owns only the card's look and its page; whichever merges second takes main in first.

## Decision log

- **2026-11-17** — Asked what a folded transcript should show → Matthew chose to copy Apple Notes: a tap on the recording opens a full page.
- **2026-11-17** — Assumed: the card shows a *Transcript ›* row with none of the words, because Matthew said "we shouldn't see anything" and the row is still a clear place to tap.
- **2026-11-17** — Assumed: the player sits at the bottom of the page, under the words, because Apple Notes puts its controls there.
- **2026-11-17** — Assumed: no tap shade at all on the row, because Matthew called the splash cheap and the page opening shows the tap.
- **2026-11-17** — Assumed: writing, failed and no-words states stay in the card with no page, because there are no words to show.
- **2026-11-17** — Assumed: the web page and the Mac app get the same page, because they share the card.
- **2026-11-17** — Assumed: in the browser's and the Mac's wide layout the recording's page covers the whole window, not only the note's pane, because the pane has no navigator of its own and task 1.3 pushes on the nearest one.
- **2026-11-17** — Assumed: the player hides while the keyboard is up on the recording's page, as the approved edit page shows, and comes back with *Done*.
- **2026-11-17** — Assumed: the page's *Back* names the note's first typed line, cut to 18 characters, else *Note*, so a long line does not push the copy button off the top.
- **2026-11-17** — Also updated `site/src/content/docs/app/on-a-computer.md`, which described the folded transcript on a computer.
- **2026-11-17** — Assumed: the TestFlight look (task 4.2) moves to an open thread after the publish, because TestFlight builds only from `main`.
- **2026-11-17** — Review fixes: the back title is cut by characters, not code units, so an emoji is never split; the device check taps `Back(.|\n)*` and waits for *Copy transcript* to go.
- **2026-11-17** — Archive checkpoint: built, reviewed (2 fixes), 978 phone tests pass locally; saved for publish on branch fix-transcript-open-splash.
