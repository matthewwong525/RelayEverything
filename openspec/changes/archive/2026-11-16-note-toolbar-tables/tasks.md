# Tasks

## 1. The note's Markdown (`mobile/lib/editor/markdown.dart`, `paste.dart`)

- [x] 1.1 Read and write `<mark class="<colour>">…</mark>` for the 5 colour names as `Attribute.background`, and leave any other `<mark>` as literal words; add `markdown_test.dart` round trips for each colour, a mark beside bold, and an unknown class, and verify they pass.
- [x] 1.2 Read and write `[words](address)` as a `link` attribute, writing a link whose words are its address as the bare address; change `withLinks` to keep links on other words; add `markdown_test.dart` round trips and a test that an auto-shown address writes no brackets, and verify they pass.
- [x] 1.3 Read a GFM table block into one `table` embed with its rows and `source`, and write `source` back when the cells are unchanged, else the plain form with `\|`; add `markdown_test.dart` round trips for a Claude-made table with alignment marks, a changed cell, a pipe in a cell, and a line of pipes that is not a table, and verify they pass.
- [x] 1.4 Make a pasted link keep its words as a link, and a pasted HTML or Markdown table paste as a table; update `paste_test.dart` (the link scenario now expects `[the menu](https://example.com/menu)`), and verify it passes.

## 2. The phone bars and the Format sheet (`mobile/lib/screens/note_bars.dart`, `note_editor.dart`)

- [x] 2.1 Make `FloatingToolBar` the full-width scrolling bar with *Text styles*, *Checklist*, *Table*, *Attach*, then *Bulleted list*, *Numbered list*, *Link*, *Indent less*, *Indent more*, *Hide keyboard*, as one ordered list with the recordings plan's *Record* right after *Attach* when it has landed (keep it there in `ReadingBar` too); add `screens_test.dart` tests that the first four show on a 375-point screen, a drag shows *Indent more*, and the bar still sits 6 points over the keyboard with the caret above it, and verify they pass.
- [x] 2.2 Add `SelectionToolBar` (B, I, U, S, *Highlight*, *Link*, *Lists* with its menu), shown while words are selected, each lit for the selection's style; add `screens_test.dart` tests for the switch both ways, bold lit on a bold word, and *Lists* → *Numbered*, and verify they pass.
- [x] 2.3 Rebuild `FormatSheet` in Apple's grouped look with the highlight pen and the colour row, and keep the colour in `Settings.highlightColour`; update the existing Format sheet tests, add tests for each style chip lit, pink highlight on and off, and the colour kept after a restart, and verify they pass.
- [x] 2.4 Add the *Link* box (filled from a copied `http(s)` address), *Change* and *Remove link* on a link, with any problem shown through `_say` (no new toast, for the plan `recently-deleted`); add `screens_test.dart` tests with a fake clipboard, and verify they pass.
- [x] 2.5 Add the space shortcut events for `# `, `## `, `### `, `- `, `* `, `1. `, `[] `, `> ` at a line start, with one Undo giving the marks back; add `screens_test.dart` tests for each mark and the Undo, and a test that a paste of `# x` is not changed by them, and verify they pass.

## 3. Tables (`mobile/lib/editor/table.dart`, `note_editor.dart`)

- [x] 3.1 Build the table `EmbedBuilder`: cells as `TextField`s in the note's style, sideways scroll when wide, a cell change written back as one Undo step after a pause or on blur; add widget tests for typing in a cell, the stored Markdown, and one Undo, and verify they pass.
- [x] 3.2 Add *Table* (2 by 2, cursor in the first cell), Return to the cell below and a new row at the end, Tab and Shift+Tab on desktop, and the page counting a focused cell as editing; add tests for each, and verify they pass.
- [x] 3.3 Add the column and row handles with their add and delete items, and *Table* in a table with *Convert to text* (tab-split lines) and *Delete table*; add tests for each item and that every row keeps its words, and verify they pass.
- [x] 3.4 Make *Find in Note* also find words in table cells; add a `screens_test.dart` test, and verify it passes.

## 4. The browser and the Mac (`note_editor.dart`, `mobile/lib/editor/shortcuts.dart`, `system_menu.dart`, `mobile/lib/mac/mac_app.dart`)

- [x] 4.1 Add *Table* to the wide layout's top bar and replace the top panel with `FormatMenu` under *Aa*, keeping the editor's focus; update `web_shell_test.dart` (the top bar's tools) and add tests that a pick closes the menu, styles the line, and leaves the cursor, and verify they pass.
- [x] 4.2 Write `shortcuts.dart` with every format key from the spec, ⌘ on macOS and Ctrl elsewhere, plus ⌥⌘1 to ⌥⌘0, joined with `pageKeys`, given to the editor only when `relay.desktop`; add tests that each key styles the line or words on both platforms and that no key acts on the phone, and verify they pass.
- [x] 4.3 Add *Bold*, *Italic*, *Underline*, *Strikethrough*, *Highlight* and *Link…* to the desktop right-click menu when words are selected; add a test, and verify it passes.
- [x] 4.4 Build the Mac app's *Format* menu from the same list in `shortcuts.dart`, as its own menu in `macMenus`, keeping *Check for Updates…* after *About* if the plan `mac-app-updates` has landed; add a `mac_shell_test.dart` test that each item is there with its keys and that *Title* styles the line, and verify it passes.

## 5. The guide and the wiki

- [x] 5.1 Update `site/src/content/docs/app/your-notes.md` with the bar, the swipe, the selection bar, highlight, links, tables, Markdown typed at a line start, and the shortcuts table with the browser's own keys; verify `node scripts/product-name.test.mjs` passes.
- [x] 5.2 Add to the phone app wiki page how a note keeps a highlight, a link and a table in Markdown, and that a table is an embed with its `source`; verify the wiki check passes.

## 6. Checks

- [x] 6.1 Write a Maestro flow in `mobile/device-check/flows/` that opens a note, swipes the bar, selects a word and makes it bold, and adds a table and types in two cells.
- [x] 6.2 Run `flutter analyze` and `flutter test` in `mobile/`, and build the web app, and verify all pass.
- [x] 6.3 `/save`, then run the device check on the saved commit with the change's flow and scenarios, and show its pictures, the real keyboard and the selection bar among them.
