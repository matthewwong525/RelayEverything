# Design

## Context

The note page (`mobile/lib/screens/note_editor.dart`) puts a `QuillEditor` with `scrollable: false` inside a `SingleChildScrollView`, and floats `FloatingToolBar` in a `Stack` over the bottom of the page. The editor scrolls the caret into view at the page's bottom edge and does not know the tool bar, so the typed line goes under it. The bar sits at `bottom: 8` plus a `SafeArea` minimum of 12: about 20 points over the keyboard. The screen test at the plan's commit shows both (`pictures/today-typing.png`).

The notes list (`mobile/lib/screens/timeline.dart`) builds `noteSliver` from `groupByDay` into `_DayGroup` cards, shared by the phone and the web app (`mobile/lib/web/`). The server keeps no pin. Note changes reach other phones through `relay_note_changes`, whose triggers move a note to a new `seq` after `UPDATE OF text, lat, place, edited_at, audio_key` (`schema/space-migrations/0011_note_sync.sql`). The phone's outbox has `notes`, `note.update` and `note.delete` routes (`mobile/lib/data/store.dart`).

The word *pin* already names the old note place (`Pin`, `pinning` in the phone store, from before #108). New names use *pinned* and *pinChangedAt* so the two never mix.

## Goals / Non-Goals

**Goals:** the caret above the tool bar; a 6-point gap; Undo and Redo; Find in Note on the phone; pins synced with newer-wins and no webhook message; a folding *Pinned* part.

**Non-Goals:** Lock, Move, Duplicate, Scan; a long-press row menu; Find in Note on the web; highlighting every match.

## Decisions

1. **Caret above the bar: a post-frame scroll to the caret.** On each selection or word change while editing or finding, and when the keyboard's height changes, the page scrolls, after the frame, so the caret rect shows 8 points under the top edge and about 64 points (`barRoom`, the tool bar's height plus its gap) above the bottom edge. It jumps, so it runs after the editor's own scroll to the bottom edge in the same frame, or stops it. `QuillEditorConfig.scrollBottomInset` was the first choice, but flutter_quill 11.6 adds the inset over the caret's top edge too, so a caret that moves up, such as by Undo far up a long note, goes about 56 points under the top edge. The page's bottom padding (120) is more than the margin, so the last line can scroll above the bar. Alternative: make the editor scrollable itself: rejected, because the date, files and voice player scroll with the words.
2. **Gap:** `Positioned(bottom: 0)` and `SafeArea(minimum: bottom 6)` while editing; the reading bar keeps 12.
3. **Undo and Redo: the `QuillController`'s own history.** `hasUndo`, `hasRedo`, `undo()`, `redo()`. The controller is made per page, so history starts at the opened words. A voice note's words that arrive later replace the document and clear history. The buttons listen to the controller and use `CupertinoIcons.arrow_uturn_left` and `arrow_uturn_right`; *Undo* is a `RoundIconButton`, and with *Redo* the two share a `ButtonPill`. A tap keeps focus with `skipRequestKeyboard` off, as the Format panel's taps do. Undo runs through `document.changes`, so the save on pause keeps it.
4. **Find in Note: a find mode on the page, no document change.** ⋯ → *Find in Note* sets `_finding`, hides the tool bar and the top ✓, and shows `FindBar` (field, *n of m* or *No matches*, clear, up, down, ✓) in the tool bar's place with its own `FocusNode`. Matches are the ranges of the query in `document.toPlainText()`, found with a case-insensitive `RegExp` of the escaped query over the words as they are, so a lowercase copy of another length never moves them. A tap in the words while finding ends find mode, as in Apple Notes, and the tool bar, ✓ and Undo come back. The current match is set as the editor's selection with `ChangeSource.silent` and scrolled into view with the same bottom inset. Selection changes no Delta, so nothing saves. ✓ clears find mode and the selection. Highlighting every match would need a format in the Delta, which the save would keep. The web pane does not list it.
5. **Pins on the server: two columns and their own route.** `0018_note_pins.sql` adds `relay_notes.pinned_at INTEGER` (NULL = not pinned) and `pin_changed_at INTEGER`, and a trigger `relay_note_changes_pinned AFTER UPDATE OF pinned_at, pin_changed_at` that moves the note's `relay_note_changes` row, as the others do. A new action `PUT notes/pin` (`relay.notes-pin`, `asDeviceOrPage`) takes `{ id | clientId, pinned, at }`, clamps `at` to now, answers 409 when the stored `pin_changed_at` is later, keeps the newer `at` even when the pin already matches, answers `pinChangedAt` by the server's clock, and logs no `relay_outbox` row, so no webhook message. `GET notes` adds `pinned` and `pinChangedAt`. Alternative: a field on `PATCH notes`: rejected, because that route requires words, logs `note.updated` and conflicts on `edited_at`, so a pin would fight a word change.
6. **Pins on the phone.** Schema step 14 adds `notes.pinned_at`, `notes.pin_changed_at` and `notes.pin_unsent` (a pin changed here that the server has not taken). A pin made here is stamped at least 1 ms after the note's last known pin change, so a phone clock behind the server's never makes it older. A pin refused as older (409) loses its unsent mark, so the next pull, which brings the newer change, sets the phone's pin. A pin the server took keeps the server's `pinChangedAt` from the answer, so a phone clock set ahead never beats a later pin made elsewhere; a pull of a note with no unsent pin takes the server's pin and time. Turning sending on to Relay Everything queues each unsent pin, because a pull reads only notes that changed on the server. A server older than pins refuses a phone key's `PUT` with 403: the phone asks `GET key`, as for photos, and drops the pin when the key answers. `Relay.pinNote(id, pinned)` writes them at once. While sending to Relay Everything it enqueues `note.pin` with `{clientId, id?, pinned, at}`; a later pin item for the same note replaces a waiting one. A note not yet uploaded sends its pin after its `notes` item, as `note.update` does. With sending off or the person's own webhook the pin stays local, and `note.pin` never goes to a webhook. The pull takes the server's pin when its `pinChangedAt` is newer than the phone's and no `note.pin` item waits for that note. `WebRelay` calls `PUT notes/pin` directly.
7. **The Pinned part.** `noteSliver` takes the shown notes (after filter and search), puts the pinned ones, newest first, in a `_DayGroup` named *Pinned* with a chevron, and gives the rest to `groupByDay`. The heading toggles a phone setting `pinnedFolded` (in `Settings`, kept with the others), with no tap shade, as Matthew asked for folding section names. The web app keeps its own fold in memory.
8. **Swipe right pins.** The row's `Dismissible` gets `startToEnd` with a pin background in the accent and `confirmDismiss` that pins and returns false, so the row stays. A screen reader gets a *Pin* or *Unpin* custom action beside *Delete*.

## Risks / Trade-offs

- The page's scroll and the editor's own scroll both answer a caret move. Widget tests check the caret rect ends above the tool bar after typing at the end of a long note, and stays under the top edge when it moves up.
- The device check draws the real keyboard, so the 6-point gap is checked only there and on TestFlight.
- An older phone ignores `pinned` in `GET notes` and shows no *Pinned*: no harm.

## UX

### Use-case brief

Matthew, one-handed on his iPhone, writes and fixes notes many times a day and keeps a few notes he opens often (a door code, a list). Done: he sees what he types, takes back a slip in one tap, finds a word in a long note, and opens a kept note from the top of the list. Mirrors Apple Notes on iOS 26, the closest existing screen. Typing and undo: many times a day; pin: a few times a month; find: a few times a week.

### Flow

Tap a note → keyboard up, caret visible above the bar → type → Undo if needed → ✓. ⋯ → *Pin Note* → back → note in *Pinned*. ⋯ → *Find in Note* → type a word → down, down → ✓. Edge: swipe right on a row to pin; tap *Pinned* to fold.

### Hierarchy

The note page keeps one accent button, ✓ while editing (compose while reading). Undo and Redo are plain round buttons, like share. In the list, *Pinned* looks like a day heading, with only a muted accent chevron to say it folds; the accent compose button stays the one bright thing.

### Components

`RoundIconButton`, `ButtonPill`, `PillIconButton`, `MoreMenu`, `_FrostedPill` (find bar), `_DayGroup` with a fold, `Dismissible`.

### Review

[review.html](review.html): the first What Changes item shows the note page while typing, the third the notes list open and folded, and the fourth the ⋯ menu and the find bar.
