# Design

## Context

The note page (`mobile/lib/screens/note_editor.dart`) runs on super_editor 0.3.0-dev.52, which draws its own text on the iPhone, Android, the Mac and the web page. See proposal.md for why we move, and [the note editor](../../../wiki/relay-note-editor.md) for the options compared. What a note must do is in `openspec/specs/relay-note-editing`, `relay-note-tables`, `relay-attachments`, `relay-notes-screen`, `relay-voice-notes`, `relay-mac-app` and `relay-note-deleting`; all of it keeps passing, except the parts this change's delta replaces.

Facts from the test on 2026-11-24 (in `.scratch/tiptap-spike/`, not kept): Tiptap 3.35.0 bundles to 462 KB of minified script; it drew a sample note in 64 ms in Chromium; a Flutter web `HtmlElementView` holding the editor in an `<iframe>` kept the frame's focus and selection when a Flutter `TextButton` under it was clicked; `postMessage` both ways carried commands and state; `webview_flutter` 4.14.1 resolves with `mobile/pubspec.lock`.

## Goals / Non-Goals

**Goals:**
- The system's own text input, selection and menus in every note, on four platforms, from one editor page.
- Every editing promise that holds today still holds, with the same stored Markdown byte for byte for a note the person did not change.
- Open as fast as today or faster.

**Non-Goals:**
- Notion tools: `/` menu, block drag, toggles, callouts (they become cheap later, on Tiptap).
- Keeping super_editor as a fallback: it comes out in this change.
- A change to sync, the server or the stored text.

## Decisions

### 1. Three layers, one owner each
```text
Flutter note page ── bars, Format sheet, Find bar, top bar, menus, files, sound, saving
      │  JSON messages (the bridge)
Editor page (Tiptap) ── the words: input, selection, marks, lists, tables, blocks, Undo
      │
Dart note model ── Markdown ⇄ editor document, paste reading, plain text for lists and search
```
- **The page owns editing.** Every keystroke, selection, typed mark, Tab, triple-click, Undo step and table cell move happens in the page, with no round trip.
- **Dart owns the text.** `editor/markdown.dart` keeps its line reader and writer and its inline runs; only its last step changes, from super_editor nodes to the editor's JSON document (ProseMirror JSON). `markdownToDoc(markdown, {title, files})` and `docToMarkdown(json)` replace `markdownToDocument` and `documentToMarkdown`; `plainText` keeps its name. The golden set in `test/markdown_test.dart` keeps its Markdown fixtures; only the middle form changes. **Why not `@tiptap/markdown`:** an early release that knows none of `<u>`, `<mark class>`, dashed versus bullet lists, `attachment:` lines, or lines under an item.
- **Flutter owns everything around the words**, as today.

### 2. The editor's document
| Our Markdown | Editor node or mark |
|---|---|
| first line (Title) | `heading` level 1, attr `title: true` |
| `#`/`##`/`###` | `heading` 1–3 |
| body, `> `, fenced code | `paragraph`, `blockquote`, `codeBlock` |
| `* `, `- `, `1. ` with indent | `bulletList` (attr `dashed`) / `orderedList`, nested `listItem` |
| `- [ ]`, `- [x]` | `taskList` / `taskItem` (`checked`) |
| line indented under an item | a second `paragraph` in that `listItem` |
| Markdown table | `table` / `tableRow` / `tableHeader` / `tableCell`, each cell one `paragraph` of plain text |
| `![name](attachment:id)` | `attachment` atom block, attrs `id`, `name`, `kind` |
| `**`, `*`, `~~`, `<u>`, `<mark class>`, `[w](a)`, `` ` `` | `bold`, `italic`, `strike`, `underline`, `highlight` (`colour`), `link` (`href`), `code` |

A bare address the page shows as a link is a `link` mark with attr `auto: true`, written back as the bare address, so showing it changes no stored word.

### 3. The editor page
`mobile/editor-web/`: an npm project with exact versions and a lock file; `@tiptap/core`, `starter-kit`, `extension-list`, `extension-table`, `extension-highlight`, `extensions` (placeholder) and our own extensions in `src/`:
- `attachment` node with a node view: picture, file row and recording card, drawn in HTML and CSS to match `screens/note_blocks.dart`; taps go to Flutter (open a file, play, seek, fold the transcript).
- Input rules: `# `, `## `, `### `, `- ` (dashed), `* `, `1. `, `[] `, `[ ] `, `> `; Undo right after a rule gives back the typed marks (`undoInputRule` bound to Undo).
- Keys: Tab and Shift+Tab sink or lift every selected item; Return in a table cell goes to the cell below and adds a row in the last row; triple-click and triple-tap select one paragraph, which is one line.
- Rules from the specs: a paste goes to Flutter (see 5); a note from elsewhere refuses a step that removes an `attachment` (a `filterTransaction`); the title line keeps its style.
- `editor.css` takes every colour, size and gap from CSS variables that the app fills from `brand.dart` and the stylesheet values in today's `editor/note_style.dart`, so the even spacing and the round circles look as they do now; `caret-color` is the words' colour; tap highlight and the iOS callout for pictures are off; motion stops under *Reduce Motion*.

esbuild writes `index.html`, `editor.js`, `editor.css` and Inter into `mobile/assets/editor/`, which `pubspec.yaml` lists. The built files are committed with `source.sha256` (the SHA-256 of `src/`, `package.json` and the lock file); a Node test fails when they differ, so the phone builds need no npm step. The page names no outside address.

### 4. The bridge
JSON objects. App → page: `load {doc, theme, editable, fromElsewhere, bottom}`, `run {action, value}` (bold, italic, underline, strike, highlight, link, line style, list kinds, indent, checklist, table add, convert or delete, undo, redo, select-all, find, find-step, insert-attachments, focus, blur, keyboard on or off), `files {id → src, length, playing, position}`, `paste {slice}`, `appKeys {keys}` (the keys the page gives back as `keys`). Page → app: `ready {ms}`, `changed {doc}` (debounced to one a frame), `state {marks, kind, inTable, canUndo, canRedo, focus, selectionRect, found}`, `paste {html, text}`, `tap {attachment, action}`, `open {address}`, `keys {shortcut}` for the app's own keys (⌘N, ⌥⌘T, ⌘F) that a focused page would swallow.

`lib/editor/web_note/` holds `WebNote`, the one Dart class the note page talks to: `load`, `run`, a `ValueListenable<NoteState>`, `onChanged`, `onPaste`, `onTap`. Behind it, by conditional import as `lib/web/paste_browser.dart` does:
- **iPhone, Android, Mac:** `webview_flutter`, `loadFlutterAsset`, transparent background, `addJavaScriptChannel('Relay')` in, `runJavaScript('relayReceive(…)')` out, a `NavigationDelegate` that refuses every other address.
- **Web page:** an `<iframe>` in an `HtmlElementView`, `postMessage` both ways, with the frame's window checked as the sender. The frame gets the built page as its own text (`srcdoc`) with a `<base>` on the editor's folder: the server answers an address that ends in `.html` with a move to the folder, which it answers with the app's page. The frame stays at the same place in the tree when the layout changes, because a move reloads it; a page that starts again (a second `ready` to load) gets the last `load` again, with each later file and setting merged into it. The frame hides itself until `ready`: Flutter draws no view at zero opacity. A bar over the words takes its own clicks (`pointer_interceptor`), and the frame takes no click while one of the app's dialogs, menus or the drawer is open.

`NoteCommands` keeps its names and reads the last `NoteState`, so `note_bars.dart` changes only its source of state.

### 5. Paste
The page catches `paste`, sends `{html, text}`, and waits. Dart runs today's `paste.dart` reader to its line model and `markdownToDoc`, and sends the slice back; the page inserts it as one step, so one Undo takes it back. A paste of one line with no line style joins the line. Copy from a note puts the page's HTML on the clipboard, which the same reader reads back with its styles. The native *Paste* of the iPhone menu fires the same event with the clipboard's HTML and no question. The `relay/clipboard` channel goes if nothing else calls it.

### 6. Files and sound in the words
The app gives each attachment a `src`: on the web page, the address the app already loads; elsewhere, a JPEG made by the app at the shown width (`instantiateImageCodec` with `targetWidth`), kept per note while it is open. A recording card is drawn in the page; its play, seek and transcript taps go to Flutter, which plays with `just_audio` as now and sends the position four times a second while playing. *Attach* and the mic send `insert-attachments` at the cursor's line, or at the end with no cursor. Removing a block and Undo work in the page's history; the note's file list follows the saved Markdown as today (`_KeepFilesReaction` becomes the page's refusal plus the same Dart check on save).

### 7. Keyboard, bars and scrolling
- **No arrow bar, and focus with no tap (iPhone).** `ios/Runner/RelayWebKeyboard.swift` swaps the web view content view's `inputAccessoryView` for nil and lets a page `focus()` raise the keyboard, the way Cordova's keyboard plugin does. Both use undocumented WebKit names; each is looked up first and skipped if absent, so a new iOS loses the nicety and never crashes. The iPhone check shows if the bar comes back.
- **Android focus.** On a new note, the host calls the web view's native `requestFocus` and shows the input method from `MainActivity.kt` before the page focuses.
- **Bar taps keep the keyboard.** The bar's buttons take no focus (`canRequestFocus: false`), as in the test; a command arrives with the selection the page still has.
- **Format sheet.** `keyboard off` sets `inputmode="none"` on the note, which drops the keyboard and keeps the cursor; `on` sets it back. The sheet takes the keyboard's last height, as now.
- **Cursor above the bar.** The `Scaffold` does not resize for the keyboard. The page gets `bottom` (keyboard inset + bar + gap) as padding and `scroll-padding-bottom`, and scrolls the selection into view after each change and on `bottom` changes. The date and the voice card above the words are part of the page, so one scroll moves all of it, as today.
- **Swipe back** stays the route's; a 20-point strip at the left edge above the web view takes the drag if the web view swallows it.

### 8. Opening fast
`WebNotePool` makes one page when the app starts and loads the editor into it, and keeps one spare; a note page takes a ready page and sends `load`. A note opened over another (a voice note over a note) takes the spare, and a new spare is made after. The page stays at zero opacity until `ready` after `load`, on the page's own background colour, so no white frame shows. The page reports `ready.ms`; a debug log line records it.

### 9. Recently Deleted and the list
Recently Deleted opens a note in the same page with `editable: false`. The list, search and previews read `plainText` as now, with no editor.

### 10. The Mac and the web page
The Mac menu bar and its Format items run through `run`, so ⌘B and the others work while the page has focus; the Edit menu's Undo, Redo and Select All run in the page, and Cut, Copy and Paste go to the web view as the system's own actions. The app's keys the page catches come back as `keys`; the app tells the page which keys are its own (`appKeys`), so ⌘F goes to the browser in the narrow web layout, which has no find bar. The web page's iframe gets the browser's own find, spell check and menu; the app's own right-click menu goes.

### 11. Tests
- **Editor page, in Chromium (Playwright), `mobile/editor-web/test/`:** typed marks and their Undo, Tab on several lines, triple-click a line in an item, Return in a table cell, a note from elsewhere refusing a file removal, the state message for each mark and kind, each `run` action, `load` then `changed` giving the same document, `ready` time under 300 ms on CI. These take over the editing tests in `test/screens_test.dart`.
- **Dart:** `markdown_test.dart` (golden set: Markdown → document → Markdown unchanged) and `paste_test.dart` keep their fixtures; `screens_test.dart`, `paste_menu_test.dart`, `mac_shell_test.dart` and `web_shell_test.dart` use a `FakeWebNote` that records `run` calls and lets a test send `changed` and `state`; a test that typed words now sends the document the page would send.
- **CI:** `mobile-ci.yml` runs `npm ci` and the editor tests with the Playwright Chromium before `flutter test`; the `source.sha256` check runs in `test.yml`.
- **iPhone check:** the note flows in `mobile/device-check/flows/` (`new-note`, `note-styles`, `paste-menu`, `note-toolbar-tables`, `media-between-words`, `recording-card`) match the web view's words through its accessibility labels.

## Risks / Trade-offs

- [The iPhone feel, the Mac and Android were not tried on a device before the build] → the iPhone check runs every note flow on the simulator with video; the person tries the TestFlight and Mac builds before the release; a failure there is fixed before *publish it?* or the change is reverted, which restores super_editor with the same stored text.
- [Undocumented WebKit names change] → looked up and skipped when absent; the arrow bar would show, nothing breaks.
- [Android keyboards in a web editor] → current ProseMirror; Gboard is the target; Android gets only its build and the browser tests here, and the report says so.
- [The OS stops the web view's process in the background] → the app saves the document on each `changed`, so a reload loses at most the last frame. On the iPhone and the Mac the host reloads the page on WebKit's `webContentProcessTerminated` error and sends `load` again, with each file and setting sent after it. Android is not handled: `webview_flutter_android` 4.13 gives no render-process-gone event, so Android's default applies and the app's process stops with the page; the app opens again with the saved note.
- [A large note is slow over the bridge] → `changed` sends at most once a frame, always the whole document; the browser test loads a note over 200 KB and checks that it is ready, and that its change comes back, in under 3 seconds.
- [The app grows] → the editor folder is about 0.6 MB with the font shared; the build prints the size.
- [Two pages in memory] → one spare only.

## Migration Plan

No data moves. One change; rollback is a revert, which brings super_editor back with the same stored Markdown.

## UX

### Use-case brief
A person writes and reads notes on an iPhone, the Mac app or the web page, often fast, with one thumb, by voice, or by paste from another app. The job: typing, selecting and fixing words must feel like the device's own Notes. Edge cases: dark mode on first open, a new note that must take typing at once, a note from elsewhere with files, a voice note opened over a note, a long note with tables and photos, Reduce Motion, VoiceOver.

### Flow
Unchanged: list → note (reading bar until a tap, then the floating bar and keyboard) → selection bar on a selection → Format sheet → back. What changes is only who draws the words, the cursor, the handles and the text menu.

### Hierarchy
The words stay the one primary thing on the page. The bars keep their order and buttons; no new control.

### Review
[The review page](review.html) and the first What Changes item (*The system's own text editing in every note*) show today's note beside the new one.

### Components
Existing: the note page's top bar, floating bar, selection bar, Format sheet, Find bar, reading bar, recording card and file row (`note_bars.dart`, `note_blocks.dart`), all kept. New: the editor page, whose look copies today's note stylesheet value for value, and whose recording card and file row copy `note_blocks.dart` in HTML, because the words and the blocks between them must be in one page for the system's selection to cross them. Removed: the app's drawn text menu and handles, replaced by the system's.
