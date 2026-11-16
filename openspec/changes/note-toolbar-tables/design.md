# Design

## Context

The note page is one Flutter screen for the phone, the browser and the Mac: `mobile/lib/screens/note_editor.dart`, with its bars in `note_bars.dart`. It edits a `flutter_quill` 11.6 document, and `mobile/lib/editor/markdown.dart` turns the document's Delta into Markdown and back, byte for byte. The server, the AI connector and webhooks only see that Markdown. Today the codec writes no links: `withLinks` takes every link mark away and marks each web address again, only for display. `relay.desktop` is true in the browser and on the Mac, and `widget.pane` is the wide layout with one top bar.

`flutter_quill` 11 has no table. It has `BlockEmbed.custom` with an `EmbedBuilder`, and the experimental `spaceShortcutEvents` and `characterShortcutEvents` in `QuillEditorConfig` for Markdown typed at a line start (with the ready-made `standardSpaceShorcutEvents`).

## Goals / Non-Goals

**Goals:**
- One set of bar parts shared by the phone and the wide layout, picked by `relay.desktop` and `widget.pane`.
- Every new style keeps a note's words readable Markdown, and an unchanged note keeps its words byte for byte.

**Non-Goals:**
- No styled text, lists or files inside a table cell.
- No change to the server, the API, or the note's stored fields.

## Decisions

### The keyboard bar and the selection bar
`FloatingToolBar` becomes a full-width frosted pill that holds a horizontal `SingleChildScrollView`. The first four buttons fit on a 375-point phone, and the fifth is cut by the edge so the scroll is visible. A `ListenableBuilder` on the controller shows `SelectionToolBar` in its place while `!selection.isCollapsed` and the editor has focus. The bars use the same `_FrostedPill` parts, and each button has a tooltip, which is also its screen-reader name.

**A place for the mic.** The plan `recordings-as-attachments` adds *Record* to `FloatingToolBar` and `ReadingBar` on the phone. It goes right after *Attach* in both: in the keyboard bar it is the fifth button, the one the edge cuts, so it also shows that the bar scrolls. The swiped tools come after it. The bar's button list is one ordered list in `note_bars.dart`, so the change that lands second adds or keeps one entry.

*Alternative:* two rows, or a ⋯ button for overflow. Not chosen: Apple's bar scrolls, and you asked for the swipe.

### The Format sheet
`FormatSheet` keeps its place (the keyboard's height, keyboard down), and is rebuilt in Apple's grouped look: a scrolling row of style labels, each drawn in its own style, then segmented groups. The highlight colour is kept in `Settings` (`highlightColour`, default purple), so it stays the same after the app closes, as on Apple Notes. The colour dot opens a row of 5 dots over the sheet.

### Highlight
The editor stores a highlight as `Attribute.background` with a value from a fixed map of 5 names to brand colours (`purple`, `pink`, `orange`, `green`, `blue`), and draws the colour at a low alpha in light and dark so that text stays readable. The codec writes `<mark class="pink">…</mark>`, and reads only those 5 class names; any other `<mark …>` stays as literal words, so old text never changes meaning. A pasted background colour is still dropped, as today.

*Alternative:* `==words==`. Not chosen: it has no colour, and some Markdown readers show it as literal `==`.

### Links on words
The codec reads `[words](address)` into a `link` attribute and writes it back. A link whose words are the same as its address is written as the bare address, so an auto-shown address never adds brackets. `withLinks` stops taking every link away: it keeps links whose words differ from the address and marks bare addresses as today. `paste.dart` keeps a link's words with the link, in place of `words (address)`. The *Link* box is a small Cupertino dialog with one field, filled from the clipboard when it holds an `http(s)` address.

### Tables
A table is one `BlockEmbed.custom` of type `table` whose data is JSON: `{"rows": [[...], ...], "source": "<the Markdown it came from>"}`. The codec reads a block of lines that is a valid GFM table (a head row, a `---` row, body rows) into that embed, and writes `source` back unchanged when the cells are unchanged, so a table from Claude keeps its exact spacing and alignment marks. A changed table is written in a plain form: `| a | b |`, `| --- | --- |`, `\|` for a pipe in a cell.

`mobile/lib/editor/table.dart` holds the `EmbedBuilder`: a horizontally scrollable `Table` of plain `TextField`s with the note's text style, and the column and row handles, which are `MoreMenu`s. A cell change is written back to the document with one `replaceText` of the embed, after a short pause or when the cell loses focus, so each pause is one Undo step. While a cell has focus, the note page counts as *editing* (the keyboard bar and ✓ show), and the bar's *Table* button opens *Convert to text* and *Delete table*. Return and Tab move between cells through each cell's `onSubmitted` and a `Shortcuts` map.

*Alternative:* a table package, such as `flutter_quill_extensions`' old table, or another editor. Not chosen: `flutter_quill` 11 dropped its table, and a new editor would put at risk the paste, find and caret work that is done.

### Markdown typed at a line start
`QuillEditorConfig.spaceShortcutEvents` gets our own list built on `SpaceShortcutEvent`: `#`, `##`, `###`, `-` (dashed, our `dashedList`), `*`, `1.`, `[]`, `>`. Each event takes the marks away and sets the line style in one change, so one Undo gives the marks back. A paste is not typing, so it does not go through these events.

### Web and Mac
The wide layout's *Aa* opens `FormatMenu`, an `OverlayPortal` anchored under the button, in place of the panel at the top of the pane. Its buttons sit in `ExcludeFocus`, so the editor keeps focus and the cursor. Escape or a click outside closes it.

The format keys live in a new `mobile/lib/editor/shortcuts.dart`: one map from `SingleActivator` to an `Intent` per action, with ⌘ on macOS and Ctrl elsewhere, given to `QuillEditorConfig.customShortcuts` and `customActions` when `relay.desktop`. The existing `pageKeys` join that map. The Mac app's `PlatformMenuBar` in `mac_app.dart` gets a *Format* menu built from the same list, so the menu and the keys can not drift. The plan `mac-app-updates` adds *Check for Updates…* after *About* in the same `macMenus` list; *Format* is its own top-level menu, so the two meet only in that list and in `mac_shell_test.dart`, and the change that lands second keeps both. On desktop, `noteContextMenu` adds the format items to the drawn right-click menu when words are selected.

## Risks / Trade-offs

- [A browser keeps some keys, such as Ctrl+Shift+T and Ctrl+Shift+N in Chrome] → also give ⌥⌘1 to ⌥⌘0 for the line styles, and list the browser's keys on the website page.
- [`spaceShortcutEvents` is marked experimental in `flutter_quill`] → the version is fixed by `pubspec.lock`, and codec and widget tests cover each event.
- [A table cell is a `TextField` outside Quill, so find, the caret scroll and paste rules do not reach it] → *Find in Note* also searches cells' words, the caret scroll uses the cell's own position, and a paste into a cell is plain words.
- [An old note that holds a pipe table as text now shows as a table] → it is shown as a table but its words stay byte for byte until the person changes the table.
- [The plan `recently-deleted` removes every `SnackBar` and adds an Apple-style alert, in the same `note_editor.dart`] → add no new `SnackBar`; a problem goes through the existing `_say`, which that plan turns into its alert; a deleted note is read-only, so the bars, the table cells and the shortcuts do not edit it. The second change to publish takes in the first's lines.
- [The recordings plan changes the same two files and the same bars] → its mic has its place after *Attach*; the second change to publish takes in the first's lines.

## Migration Plan

No data move. Old notes open as before. A note gains `<mark>`, `[words](address)` or a table only when the person adds one.

## UX

### Use-case brief
You write notes on an iPhone, many times a day, often with one thumb, and you sometimes edit them at a desk in the browser or the Mac app. The job is to style what you write fast: a heading, a list, a table of stops, a highlighted thing to do. Done is the note looking the way you mean it, with no hunt for a tool. Common case: type with the keyboard up and tap a style. Edge cases: a long table on a small phone, a link to add, a style on a computer with no touch.

### Flow
Phone: tap into a note → the bar shows *Aa*, *Checklist*, *Table*, *Attach* → swipe for more, or select words for the style bar → *Aa* opens the Format sheet in the keyboard's place → ✕ brings the keyboard back. Computer: click *Aa* in the top bar → pick in the menu → typing goes on; or use the keys.

### Hierarchy
The words are the screen. The bar is the one tool area, frosted and quiet; the accent is only on ✓ and on the current style in the Format sheet. The table's handles show only on the cell in use.

### Review
[review.html](review.html), items 1 to 3 (the phone bars and the Format sheet), item 6 (tables) and item 8 (the web and Mac menu).

### Components
Reused: `_FrostedPill`, `PillIconButton`, `RoundIconButton`, `MoreMenu`, `ButtonPill`, `noteStyles`. New: `SelectionToolBar`, the scrolling `FloatingToolBar`, the rebuilt `FormatSheet`, `FormatMenu` for the wide layout, the table embed, all in Apple's style with `CupertinoIcons`, after the closest screens: today's Format sheet and the wide layout's top bar.
