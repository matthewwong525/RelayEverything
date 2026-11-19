# Proposal

**Status:** in-progress
**Branch:** `triple-click-selects-whole-line`
**Open questions:** none

## Why

Editing a note does not feel like a good document editor. A triple-click does not select a line. A pasted plan with numbered items shows *a.* on every item, and its *Why:* lines get more space than the items. The editor we use today, flutter_quill, knows only single and double clicks, and each fix fights it. We move the note to super_editor, an editor made of blocks, as Notion is, and we fix how a paste reads lists.

## What Changes

- **A triple-click selects the whole line.** On the Mac app and the web page, a third quick click selects the line under the pointer. On a phone, a third quick tap does the same. The line ends at a line break, so a triple-click on an item selects only that item, not the *Why:* line under it.
  ```page
  After: pages/after-select.html
  ```
- **A pasted list keeps its shape.** Numbered items show 1, 2, 3, as you copied them. A list typed two spaces in, under a line such as *Assembly — …*, pastes as a list, not as a sub-list with letters. A line indented under an item, such as *Why: Pallet leaves Fri*, stays under that item, and the next item keeps counting. Bullets that start with `-` paste as dashed items, as today.
  ```page
  Before: pages/before.html
  After: pages/after.html
  ```
- **The spacing is even.** Each line in a note has the same space above it: paragraphs, list items, checklist items and the line under an item. A heading gets the same space above it everywhere. An empty line adds one even gap. This shows on the phone, the Mac app and the web page.
  ```page
  After: pages/after.html
  ```
- **A new editor under the note, with the same look and tools.** Everything you do in a note today still works the same way:
  | Today's part | After the change |
  |---|---|
  | Format sheet, keyboard bar, selection bar | Same buttons, same look |
  | Checklists with round circles, dashed lists | Same |
  | Tables, photos, files and recordings in the words | Same, still editable |
  | The iPhone's own text menu, Paste with no question | Same |
  | Find in Note, Undo and Redo, Mac keys | Same |
  | Notes kept as Markdown | Same text; old notes open as they are |

  Notes stay saved as the same Markdown, so nothing in your space changes, and AI apps and webhooks see the same text.

## What the build needs

- **Nothing.** super_editor is a free package from pub.dev.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-note-editing`: a triple-click or triple-tap selects a line; a pasted list keeps its numbers, its level and the lines under its items; every line has the same space above it.

## Impact

- Phone, Mac and web app (`mobile/`): `flutter_quill` comes out of `pubspec.yaml` and `super_editor` (0.3.0-dev.52, pinned) goes in. The two can't be installed together (both need different `dart_quill_delta`), so the switch is one change.
- Rewritten on super_editor: `screens/note_editor.dart`, `screens/note_bars.dart`, `screens/recently_deleted.dart`, and `editor/markdown.dart`, `paste.dart`, `table.dart`, `attachments.dart`, `system_menu.dart`, `magnifier.dart`, `shortcuts.dart`; `screens/timeline.dart` loses its one quill use.
- Tests reworked: `test/markdown_test.dart`, `paste_test.dart`, `paste_menu_test.dart`, `screens_test.dart`, `web_shell_test.dart`, `mac_shell_test.dart`.
- No server, API or data change. The website's notes page gains one line on triple-click.
- Non-goals: a `/` menu or drag handles to move lines (asked: not needed now); a new look for the note page.

## Decision log

- **2026-11-18** — Asked whether to fix on flutter_quill or change the editor → chose to replace flutter_quill with super_editor.
- **2026-11-18** — Asked which parts of Notion matter → chose *Paste keeps its shape*, *Clicks and selection* and *Even spacing*; not the `/` menu or drag handles.
- **2026-11-18** — The person asked me to research and decide the editor. Chose super_editor over AppFlowy Editor, Fleather and a web editor in a web view, because super_editor is updated this month, has triple-click on mouse and iPhone, and resolves with the app's packages; AppFlowy Editor needs `file_picker` 10 against our 13 and was last updated in August; Fleather keeps Quill's model, so it fixes none of this; a web editor would not feel native on the iPhone and would rebuild every bar.
- **2026-11-18** — Assumed: notes stay stored as today's Markdown, read and written by our own reader, because the server, AI apps, webhooks and old notes depend on that text, and super_editor's own Markdown reader does not know our dashed lists, checklists, tables and file lines.
- **2026-11-18** — Assumed: a line under a list item is part of that item, after a line break inside it, and is stored as a Markdown line indented under the item, because that is how Markdown keeps it in the item, so the numbers keep counting.
- **2026-11-18** — Assumed: a triple-click selects to the nearest line break, also a break inside an item, because the person asked for the whole line, not the whole item.
- **2026-11-18** — Assumed: a list whose first item is indented and has no list above it starts at the first level, because Markdown ignores up to three spaces before a list, and a copied plan indents its lists under a label.
- **2026-11-18** — Assumed: one change with no side-by-side period, because the two editors can't be installed together.
- **2026-11-18** — Assumed: super_editor is pinned to one exact version, because it is still a pre-release and a new one can change its parts.
- **2026-11-18** — Assumed: task 1.1's golden set ran on the new reader and writer only, not first on Quill's, because the build writes all code before any test runs; today's Markdown tests are the golden set, kept as they were.
- **2026-11-18** — Assumed: Undo and Redo use the note's own snapshot history, because a paste, a table edit and a file move must each undo in one step.
- **2026-11-18** — Assumed: two code blocks that touch are written with no empty line between them, because the new writer keeps each code line as its own block.
- **2026-11-18** — Assumed: a typed mark such as `# ` acts only at the start of a line and only for a typed space, so a paste of `# x` stays words.
- **2026-11-18** — Assumed: a checklist item also keeps the lines under it, as a list item does; an HTML `<li>` with a line break pastes as one line.
- **2026-11-18** — Assumed: the spacing keeps Quill's measures, so the page looks the same except that it is even.
- **2026-11-18** — Assumed: on the Mac a styled paste reads the page's HTML through the app's `relay/clipboard` channel, because Flutter's clipboard gives plain words only.
- **2026-11-18** — Assumed: on an iPhone a triple tap selects the line and shows no menu, and a hold selects the word under the finger, as super_editor does; super_editor's own magnifier replaces the tinted one, so `editor/magnifier.dart` goes.
- **2026-11-18** — Assumed: the selection stays when the note loses focus, and a tap on the cursor in the 300 ms after the iPhone closes its menu opens nothing, so the tap that closes the menu does not open it again.
- **2026-11-18** — Assumed: Monostyled, a line style and the quote bar act on each line; a line style on a list item makes it a plain line.
- **2026-11-18** — Assumed: typing at a photo or a file starts a line of its own; in a note from elsewhere a change that takes a file away is undone in the same step.
- **2026-11-18** — Assumed: the computer's right-click menu is drawn by the app, and Android's text menu runs the note's own Cut, Copy, Paste and Select All, so styles and tables keep on copy.
- **2026-11-18** — Assumed: `follow_the_leader` is a direct dependency, because the note's own iPhone and Android menus take its `LeaderLink`; it was already in the lock file through super_editor.
- **2026-11-18** — Assumed: a photo, file or table is drawn in our own selection box, not super_editor's `SelectableBox`, because that box blocks every tap, so a file would not open and a cell would not take the cursor.
- **2026-11-18** — Assumed: a file the server no longer has leaves the words but stays in the Undo steps, so Undo of a backspace that took a photo brings it back, as before.
- **2026-11-18** — Assumed: each note page has its own keyboard role, so a note opened over another note does not fight it for the keyboard.
- **2026-11-18** — Check: four note-page tests wait a double tap's time (300 ms) after a tap, or a short pause after a selection on a photo, because super_editor waits that long to know a tap is single.
- **2026-11-18** — Check: in `paste_menu_test.dart` the menu after a backwards selection must point above the title's middle, not its top, because super_editor points at the selected line's box, which starts a little under the title's top; the menu after a hold lists the selection items too, because a hold now selects a word.
- **2026-11-19** — Assumed: a quiet change, such as a file the server no longer has leaving the words, is not put back in a note from elsewhere, because only the person's own change must keep the note's files; else the gone file's line stays and is sent.
- **2026-11-19** — Assumed: the iPhone, iPad and Android runners answer `relay/clipboard` with the clipboard's HTML, as the Mac does, so the app's own Paste and ⌘V or Ctrl+V keep styles; the iPhone reads the HTML only when the clipboard's types name formatted words.
- **2026-11-19** — Assumed: iOS 15's drawn text menu is the app's own copy of super_editor's, with Select All added, because super_editor's takes no more items; `overlord` becomes a direct dependency for it, already in the lock file through super_editor. The drawn menus follow the selection, so Cut and Copy show after Select All.
- **2026-11-19** — Assumed: a `<br>` inside a page's list item starts a line in that item, not a new item, so the list counts on past it; this replaces *an HTML `<li>` with a line break pastes as one line*.
- **2026-11-19** — Assumed: blank lines inside a list item stay in it while a later line indented to its words still continues the item, as Markdown reads them; with no such line, a blank line ends the item as before.
- **2026-11-19** — Assumed: the web page's paste test sends the browser's paste event through a test hook in `web/paste_none.dart`, because a test runs outside a browser.
- **2026-11-19** — Assumed: a blank line inside a list item is written with no spaces, so a stored note with a truly blank line in an item saves back unchanged after any other edit.
- **2026-11-19** — Saved for the final checks: the build and two review rounds are done, and the iPhone simulator check (7.2) and the Mac and web previews (7.3) run on this save.
- **2026-11-19** — Assumed: the share extension and the watch targets get their own build settings files (`ios/Flutter/Extension-*.xcconfig`), because super_keyboard, which super_editor needs, has no Swift package, so the iPhone build now uses CocoaPods, and the Runner's pods must not link into the watch.
- **2026-11-19** — Assumed: super_keyboard builds against Android 36 from `android/build.gradle.kts`, because it asks for 34 and its own dependencies need 36.
- **2026-11-19** — Check: task 7.3 ran on the web page built from this commit with made-up notes in a local browser, at computer and phone width, because a preview page can't sign in; the Mac app was not opened, because no Mac runs here; its build passes in CI, and the Mac and the web page share the same mouse code. A triple-click selected one item and not its *Why:* line, a double-click selected one word, a pasted plan showed 1, 2, 3 with its *Why:* lines, a styled paste counted on past a sub-list, and the spacing was even.
- **2026-11-19** — Check: the iPhone tour's *paste-menu* step opens the menu from a tap on the cursor, not from a second hold, because a hold now selects words and a paste over the same words looks unchanged; the first run failed only on that, and its video shows the paste put the words in with no question.
