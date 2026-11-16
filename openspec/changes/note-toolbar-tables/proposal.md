# A toolbar like Apple Notes, tables in notes, and editing made for each device

**Status:** in-progress
**Branch:** apple-style-toolbar-editor
**Open questions:** none

## Why

On 2026-11-16 you compared the note page with Apple Notes on iOS 26. Our bar over the keyboard has only three buttons: *Aa*, *Checklist* and *Attach*. Apple's bar has more tools, and you swipe it left to see the rest. When you select words, Apple's bar changes to bold, italic, underline, strikethrough, highlight, link and lists. Apple also has tables. Our note page also works the same in the browser and on the Mac as on a phone, but a computer needs a menu and keyboard shortcuts, like Notes on a Mac.

## What Changes

- **The bar over the keyboard has more tools, and you swipe it for the rest.** The bar is now as wide as the screen. It shows *Aa*, *Checklist*, *Table* and *Attach* first. Swipe it left to get *Bulleted list*, *Numbered list*, *Link*, *Indent less*, *Indent more* and *Hide keyboard*. Part of the next button shows at the right edge, so you can see that the bar scrolls. There are no drawing or AI buttons. The plan *Recordings go in a note like files* adds a mic button. It goes right after *Attach*, in this bar and in the bar at the bottom while you read. The phone only: the browser does not record.
  ```picture
  Today: pictures/today-bar.webp
  After: pictures/after-bar.webp
  Swiped left: pictures/after-bar-swiped.webp
  ```
  No real picture of the keyboard: only an iPhone draws it, so the space under the bar is empty. The device check takes the real picture at /verify.
- **When you select words, the bar changes to their styles.** It shows **B**, *I*, U, S, *Highlight*, *Link* and *Lists*. A button lights up when the selected words have that style. *Lists* opens a small menu: *Bulleted*, *Dashed* and *Numbered*. When the selection goes, the bar changes back.
  ```picture
  After: pictures/after-selection.webp
  ```
  No real picture of the iPhone's own Cut, Copy and Paste menu, which shows over the selection: only an iPhone draws it.
- **The Format sheet looks like Apple's.** *Aa* opens it in the keyboard's place. At the top are the line styles, each shown in its own look: *Title*, *Heading*, *Subheading*, *Body* and *Monostyled*. The current one is filled, and you swipe the row to see the others. Under them are B I U S in one group, then the highlight pen and a coloured dot. The last row has the three lists, indent less and indent more, and block quote. A tap on the coloured dot shows 5 colours: purple, pink, orange, green and blue. ✕ brings the keyboard back.
  ```picture
  Today: pictures/today-format.webp
  After: pictures/after-format.webp
  Colours: pictures/after-colors.webp
  ```
- **Highlight words in a colour.** Select words, then tap the pen. The words get a highlight in the current colour. A tap on the pen again removes it. The note saves it as Markdown text, for example `<mark class="pink">book the hall</mark>`, the same way underline is saved today as `<u>…</u>`. Claude, the API and your webhooks see these words with the tag.
- **Link any words.** Select words and tap *Link*. A small box asks for the address. It is already filled in when you copied an address. The words show as a link, and the note saves them as `[book the hall](https://example.com)`. Tap *Link* in a link to change its address or remove the link. A web address that you type still becomes a link by itself, as it does today. A pasted link now keeps its own words as a link, and does not add the address in brackets.
- **Tables in a note.** *Table* adds a table with 2 columns and 2 rows, with the cursor in the first cell. Type in a cell. *Return* goes to the cell below, and in the last row it adds a new row. When the cursor is in a cell, a small ⋯ handle shows on top of its column and at the left of its row. The column handle offers *Add column before*, *Add column after* and *Delete column*. The row handle offers *Add row above*, *Add row below* and *Delete row*. A wide table scrolls sideways in the note. *Table* in a table offers *Convert to text* and *Delete table*. A cell holds plain words, with no styles. The note saves the table as a Markdown table (`| Stop | Date |`), so Claude and webhooks read it as rows and columns.
  ```picture
  After: pictures/after-table.webp
  ```
- **Type Markdown to style a line.** At the start of a line, type `# ` for a Title, `## ` for a Heading, `### ` for a Subheading, `- ` for a dashed list, `* ` for a bulleted list, `1. ` for a numbered list, `[] ` for a checklist, or `> ` for a quote. The marks go and the line takes the style. *Undo* gives the marks back. This works on the phone, in the browser and on the Mac.
- **In the browser and on the Mac, Aa opens a menu like Notes on a Mac.** The top bar gets a *Table* button. *Aa* opens a menu under it: B I U S, the highlight pen and the colour dot at the top, then *Title*, *Heading*, *Subheading*, *Body*, *Monostyled*, *Bulleted List*, *Dashed List* and *Numbered List*, each shown in its own look, with a ✓ at the current one, then *Block Quote*. A click on a style closes the menu, and the cursor stays in the note. The panel that opened above the note today goes away.
  ```picture
  Today: pictures/today-web.webp
  After: pictures/after-web.webp
  ```
- **Keyboard shortcuts on the web and the Mac.** They are the same keys as Notes on a Mac. Use ⌘ on a Mac and Ctrl on Windows and Linux.
  | Do | Keys |
  | --- | --- |
  | Bold, italic, underline | ⌘B, ⌘I, ⌘U |
  | Strikethrough | ⇧⌘X |
  | Highlight | ⇧⌘E |
  | Title, Heading, Subheading, Body | ⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, and also ⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘0 |
  | Monostyled | ⇧⌘M |
  | Bulleted, dashed, numbered list | ⇧⌘7, ⇧⌘8, ⇧⌘9 |
  | Checklist, tick a checklist line | ⇧⌘L, ⇧⌘U |
  | Block quote | ⌘' |
  | Indent more, indent less | ⌘], ⌘[ (and Tab, ⇧Tab in a list) |
  | Link | ⌘K |
  | Table | ⌥⌘T |
  | In a table: next cell, cell before | Tab, ⇧Tab (Tab in the last cell adds a row) |
  A browser keeps some keys for itself, such as ⇧⌘T, which opens a closed tab again. For these, use the ⌥⌘ number keys. The Mac app's menu bar gets a *Format* menu with each of these items and its keys. A right-click on selected words in the browser and on the Mac also offers *Bold*, *Italic*, *Underline*, *Strikethrough*, *Highlight* and *Link…*.
- **The website says how.** The *Your notes* page on the website tells about the bar, the selection bar, highlight, links, tables, the Markdown you type, and the shortcuts.

Non-goals: no drawing, no Apple Intelligence or other AI writing tools, no scan, and no text colour (colour is only for highlight). A table cell has no styles, lists or pictures. No floating bar over selected words in the browser or on the Mac.

## What the build needs

- **Nothing.** The real keyboard, the iPhone's text menu and a swipe on the bar show only on an iPhone: the device check takes them at /verify, and you try them on the next TestFlight build.

## Capabilities

### New Capabilities

- `relay-note-tables`: add a table from the bar or with ⌥⌘T; edit cells; add and delete rows and columns with the ⋯ handles; Tab and Return in a table; convert to text or delete; saved as a Markdown table that opens the same again.

### Modified Capabilities

- `relay-note-editing`: the keyboard bar is full width with more tools and swipes; the selection bar; the Format sheet's new look with highlight and colours; highlight and links saved as Markdown; links on any words; Markdown typed at a line start; a pasted link keeps its words as a link.
- `relay-web-app`: the top bar gets *Table*; *Aa* opens the Mac-style menu, not a panel; keyboard shortcuts and the right-click format items in the browser.
- `relay-mac-app`: the menu bar's *Format* menu with every format item and its keys.

## Impact

- Phone and shared editor: `mobile/lib/screens/note_bars.dart` (`FloatingToolBar` becomes a scrolling bar, a new selection bar, the new `FormatSheet`, the colour row, the web `FormatMenu`), `mobile/lib/screens/note_editor.dart` (bar choice by selection, link box, Table actions, the pane bar's Table button and menu, shortcuts), `mobile/lib/editor/markdown.dart` (`<mark class>`, `[words](address)`, tables, in both directions), `mobile/lib/editor/paste.dart` (links keep their words), a new `mobile/lib/editor/table.dart` (the table embed and its cell editing), a new `mobile/lib/editor/shortcuts.dart` (keys and Markdown typed at a line start), `mobile/lib/editor/system_menu.dart` (right-click format items on desktop), `mobile/lib/mac/mac_app.dart` (the *Format* menu).
- No server change: the note's words stay Markdown text, with no new field.
- Docs: `site/src/content/docs/app/your-notes.md`.
- Tests: Markdown codec round trips for highlight, links and tables; widget tests for each bar, the Format sheet, the web menu, tables and shortcuts; a Maestro flow for the bar, the selection bar and a table.
- Another open chat, *Recordings go in a note like files* (plan `recordings-as-attachments`), also changes `note_editor.dart` and `note_bars.dart` and adds a mic to `FloatingToolBar` and `ReadingBar`. Its mic goes right after *Attach* in both. The second of the two to be published takes in the first's changes.
- Another open chat, *The Mac app updates itself* (plan `mac-app-updates`), adds *Check for Updates…* after *About* in `macMenus` in `mobile/lib/mac/mac_app.dart`, with tests in `mobile/test/mac_shell_test.dart`. Task 4.4 adds the *Format* menu and its test in the same two files. The second of the two to be published takes in the other's menu lines.
- Another open chat, *Delete like Apple Notes* (plan `recently-deleted`), removes every toast on the phone, the web page and the Mac, shows problems as an Apple-style alert, and opens a deleted note read-only. It changes the same `note_editor.dart` and editor. This change adds no new toast: a problem, such as a link address that does not open, shows in that alert, or in `_say` until it lands. The second of the two to be published takes in the other's lines.

## Decision log

- **2026-11-16** — Asked whether to plan here while the voice-notes chat changes the same note page → chose keep going here.
- **2026-11-16** — Asked about highlight and colour → chose highlight in a few colours, saved with a colour tag in the words.
- **2026-11-16** — Asked about a link button → chose yes, link any words, saved as Markdown `[words](address)`; you asked if it is all Markdown: yes.
- **2026-11-16** — Asked how the web and the Mac should format → chose like Notes on a Mac: the *Aa* menu, Mac Notes shortcuts, right-click format items, no floating bar. You then sent a picture of the Mac *Aa* menu, which the new menu follows.
- **2026-11-16** — Told by the daily line-up: the plan *Recordings go in a note like files* adds a mic to the same bars → kept its place right after *Attach* on the phone; whichever lands second takes the other's lines.
- **2026-11-16** — Told by the daily line-up: the plan *The Mac app updates itself* adds *Check for Updates…* to the same Mac menu list and test file → named the overlap; whichever lands second takes in the other's menu lines.
- **2026-11-16** — Told by the daily line-up: the plan *Delete like Apple Notes* removes all toasts and changes the same note screen → this change adds no new toast and uses its alert for problems; whichever lands second takes in the other's lines.
- **2026-11-16** — Assumed: tables save as Markdown tables, because notes are Markdown and Claude and webhooks read a Markdown table as rows and columns.
- **2026-11-16** — Assumed: a table cell holds plain words only, because a table with styled cells needs a full editor in each cell; Apple Notes allows styles, so it can come later.
- **2026-11-16** — Assumed: the 5 highlight colours are Apple's (purple, pink, orange, green, blue), with purple first as Apple has it.
- **2026-11-16** — Assumed: the swiped part of the bar holds bulleted and numbered lists, link, indent and hide keyboard, because they are the most used tools that are not already in the first four.
- **2026-11-16** — Assumed: a pasted link now keeps its words as a link, because links can now be saved; today it adds the address in brackets.
- **2026-11-16** — Assumed: Markdown typed at a line start turns into the style on every device, because it is fast with a keyboard and Apple Notes does the same for lists.
- **2026-11-16** — Assumed: the web also takes ⌥⌘1, ⌥⌘2, ⌥⌘3 and ⌥⌘0 for line styles, because browsers keep ⇧⌘T and some other Mac Notes keys.
- **2026-11-16** — Assumed: a nested HTML table, or one with a single cell, pastes as words, because it does not fit rows and columns.
- **2026-11-16** — Assumed: link words that are a piece of their own address, such as `example.com` left from `https://example.com`, lose the link, because they were an address that was edited.
- **2026-11-16** — Assumed: while a cell has the cursor, only *Table*, *Attach* and *Hide keyboard* act in the bar, and *Hide keyboard* is the same as *Done*, because the other tools style the note's words, not a cell.
- **2026-11-16** — Assumed: a colour picked while words have a highlight changes that highlight's colour, as Apple Notes does.
- **2026-11-16** — Assumed: *Link* with no words picked adds the address as its own linked words.
- **2026-11-16** — Assumed: the style bar spreads its buttons to fit the screen instead of scrolling, because 7 buttons fit on a 375-point screen.
- **2026-11-16** — Assumed: after *Delete column* or *Delete row*, the cursor goes to the next column or row, as in Apple Notes.
- **2026-11-16** — Assumed: the keys table lives on the guide's computer page, which owns the keys; the notes page links to it.
- **2026-11-16** — Assumed: the phone app wiki page for task 5.2 is `mobile/README.md`.
- **2026-11-16** — Assumed: Ctrl+Alt+digit keys do nothing when AltGr makes them on Windows and Linux, because AltGr types characters such as } on many European keyboards.
- **2026-11-16** — Built and checked on this computer: 908 phone tests pass, the code check is clean, and the web app builds. The second look found 7 problems, all fixed. Saved for the device check (task 6.3).
