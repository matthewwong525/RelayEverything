# Proposal

**Status:** in-progress
**Branch:** `notion-like-note-editor`
**Open questions:** none

## Why

Typing and selecting in a note feel cheap, and so do the look and the motion. Every Flutter editor draws its own text and copies the phone's cursor, handles and keyboard behavior, so more work on today's editor cannot fix that. We move the words of a note to Tiptap, the web editor behind many Notion-like apps, which uses the system's own text editing on each platform. A test on 2026-11-24 in a browser showed it works with our bars: the cursor stays in the note when a bar button is tapped.

## What Changes

- **The system's own text editing in every note.** On the iPhone the cursor, the selection handles, the magnifier, the text menu, autocorrect, dictation and the space-bar cursor are the iPhone's own, as in Notes. Android uses its own handles and menu, the Mac app gets the Mac's spell check and right-click menu, and the web page gets the browser's own selection, spell check and find. Everyone gets this at once, with no switch.
  ```page
  Before: pages/before.html
  After: pages/after.html
  ```
- **Everything else in a note stays the same.** The look, the bars and every tool work as today:
  | Today's part | After the change |
  |---|---|
  | Floating bar, selection bar, Format sheet, reading bar | Same buttons, same look |
  | Title, headings, checklists, dashed and numbered lists, quotes, highlights, links | Same, with the same even spacing |
  | Typed marks such as `# `, `- `, `[] ` | Same, and one Undo gives back the marks |
  | Tables, photos, files and recordings in the words | Same, still editable, with the same recording card |
  | Paste that keeps headings, lists, bold and links | Same, with no *Allow Paste?* question |
  | Triple-click or triple-tap on a line, Tab on several lines | Same |
  | Find in Note, Undo and Redo, Mac keys and menus | Same |
  | Notes kept as Markdown | Same text; old notes open as they are |
- **The note opens fast.** A note shows its words in about half a second or less, with no white flash in dark mode, and a new note opens with the keyboard up.
- **Better for screen readers.** VoiceOver and TalkBack read and edit the note's words, as they do in a web page.
- **Today's editor goes.** The old editor comes out of the app, on the phone, the Mac and the web page.

## What the build needs

- **Nothing.** Tiptap and the web view part are free and open source (MIT and BSD). The iPhone check runs on GitHub's Mac, which is set up.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-note-editing`: the text menu, handles and magnifier are the system's own on every platform, not only on iPhones from iOS 16; new promises for the system's text editing (autocorrect, dictation, spell check, browser find), for a fast open with no flash, and for screen readers.
- `relay-web-app`: a right-click in a note shows the browser's own menu, not the app's.

## Impact

- Phone, Mac and web app (`mobile/`):
  - New: the editor page in `mobile/editor-web/` (Tiptap 3, esbuild), built into `mobile/assets/editor/`; `lib/editor/web_note/` with the bridge, a host on `webview_flutter` for iPhone, Android and Mac, and a frame host for the web page; `webview_flutter` in `pubspec.yaml`.
  - Rewritten: `screens/note_editor.dart`, `screens/note_bars.dart`, `screens/recently_deleted.dart`, `editor/note_commands.dart`, `editor/note_editing.dart`, `editor/markdown.dart` (Markdown to the editor's document and back), `editor/paste.dart` (same reader, new output), `editor/table.dart`, `editor/attachments.dart`, `editor/links.dart`, `editor/shortcuts.dart`.
  - Removed: `editor/note_style.dart`, `editor/system_menu.dart`; `super_editor`, `follow_the_leader` and `overlord` from `pubspec.yaml`.
  - iPhone runner: `ios/Runner/RelayWebKeyboard.swift`, so there is no arrow bar over the keyboard and a new note can raise the keyboard. Mac and Android runner settings as the web view needs.
- Tests: the editing tests move to the editor page and run in a real browser (Playwright with Chromium) in phone CI; the Flutter tests keep the page, the bars, saving and sync, with a fake editor; the Markdown and paste tests stay in Dart; the iPhone check's note steps change to the web view.
- Docs: [the note editor](../../../wiki/relay-note-editor.md) wiki page, `mobile/README.md`, and the website's notes pages (`site/`) where they name the editor's behavior.
- No server, API or stored data change.
- Non-goals: a `/` menu, handles to drag blocks, toggles and callouts; a new look for the note page; a new Markdown mark.

## Decision log

- **2026-11-24** — Asked what feels cheap in the note editor today → chose *Typing and selecting* and *The look and motion*, not *Missing Notion tools*.
- **2026-11-24** — Asked which way to go for the note editor → chose *Test Tiptap first*, over *Add tools to today's editor*.
- **2026-11-24** — Check: Tiptap 3.35.0 in a phone-sized browser drew the sample note in 64 ms; the bar's bold reached the words and the page sent back the lit state; `## `, `[ ] `, `- ` and `> ` turned into styles; a paste from a web page kept its heading, bold, link and nested list; the browser's own spell check showed. A pasted table was lost, because the test had no table part.
- **2026-11-24** — Check: inside a small Flutter web app, the editor in a frame under a Flutter bar kept the cursor and the keyboard's focus after a click on bold, italic and *Checklist*, the typing went on in the new style, the bar lit its buttons from the page's messages, and Ctrl+B inside the note worked.
- **2026-11-24** — Check: `webview_flutter` 4.14.1 resolves with the app's packages. Android could not be tried on this computer (no emulator support), and the iPhone and the Mac need a Mac.
- **2026-11-24** — Asked how the new editor should reach real notes → chose *Replace it everywhere now*, over a hidden switch first and over the test page alone.
- **2026-11-24** — Assumed: Tiptap 3, not BlockNote, Lexical or Milkdown, because Tiptap and its parts are MIT, the phone wrappers found all use it, and BlockNote's block drag does not work by touch and its extra packages are GPL.
- **2026-11-24** — Assumed: the Flutter team's `webview_flutter`, not `flutter_inappwebview`, because that package's last stable release is two years old; the one thing it adds for us, no bar over the iPhone keyboard, is a small piece of iPhone code of our own.
- **2026-11-24** — Assumed: our Dart code stays the one reader and writer of a note's Markdown and of a paste, and the page gets and gives the editor's document, because that code and its tests already know our marks, and Tiptap's Markdown reader is an early release that does not.
- **2026-11-24** — Assumed: a line under a list item, such as *Why:*, is its own paragraph inside the item, because a browser's triple-click then selects that line alone, as the spec asks.
- **2026-11-24** — Assumed: photos show in the page from small copies the app makes, and a recording card is drawn in the page while the app plays the sound, because the page can't read the app's files and the sound already plays from the app.
- **2026-11-24** — Assumed: one editor page is made when the app starts and kept ready, with a second for a note opened over another, because a new web view each time would make each note slow to open.
- **2026-11-24** — Assumed: Recently Deleted shows a note in the same editor page, read only, because one look for a note is simpler than a second drawing of it.
- **2026-11-24** — Assumed: the system's own text menu replaces the app's drawn one on older iPhones, Android and the Mac, because a web view always has the system's menu; Paste in it keeps the formatting.
- **2026-11-24** — Assumed: the Mac's paste no longer reads the page's HTML through the app's own clipboard channel, because the web view gets it with the paste; the channel goes if nothing else uses it.
- **2026-11-24** — Assumed: the website's notes pages get a line on the system's own editing, because each app change updates its page.
- **2026-11-24** — Assumed: Android is checked only by its build and the browser tests, because no Android device or emulator can run here, and the report says so.
- **2026-11-24** — Assumed: the build wrote all source and tests first and ran the checks once at the end, because the build helper asks for that order.
- **2026-11-24** — Assumed: the page's document is flat (a list item, a heading and a paragraph carry an `indent`), not lists inside lists, because the Dart reader and writer already keep lines flat, and Tab then moves every selected line by one change of a number.
- **2026-11-24** — Assumed: a picture that is too large or of another type goes to the page as a PNG at the shown width, not a JPEG, because Flutter's own encoder writes only PNG.
- **2026-11-24** — Assumed: the web page keeps no spare editor page, because a frame loads its page only once it is on the screen.
- **2026-11-24** — Assumed: a file from *Attach* or the mic goes at the cursor while typing and at the end while reading, and a file from elsewhere goes at the end as no edit, because that is today's rule.
- **2026-11-24** — Assumed: a recording or file with no id of its own is named `head:N` in the page, in the order of the note's recordings then its files, because the page needs one key for each card.
- **2026-11-24** — Assumed: the Mac app gives the page no format keys (its *Format* menu does them) and passes only *delete note* up; the web page does the format keys in the page and passes up new note, find and delete note; a phone passes none.
- **2026-11-24** — Assumed: `WebNote.typing` (a page with the keyboard's focus) replaces the old editor's focus check, so a shake or ⌘Z undoes the typing, not a delete, as before.
- **2026-11-24** — Assumed: `focus` with `new-line` puts the cursor on an empty last line, adding one as an Undo step, for *Checklist* and *Table* while reading.
- **2026-11-24** — Assumed: a pasted file line becomes a file only when the note keeps that file, because a file line copied from another note would point at a file this note does not have.
- **2026-11-24** — Assumed: the app sends the page `highlight` with the pen's new colour when it changes, so the page's highlight key uses the colour picked last.
- **2026-11-24** — Assumed: the Android keyboard for a new note comes from `MainActivity.kt` on the same `relay/web-keyboard` channel as the iPhone's, because an Android web view also raises no keyboard from a page's own focus.
- **2026-11-24** — Assumed: the iPhone check's flows keep finding the note's words by their text, because a web view gives each line its own label; only `media-between-words` and the comments of two other flows change.
- **2026-11-24** — Assumed: the web view's script channel is named `relayBridge`, a hidden name, because `scripts/product-name.test.mjs` refuses a bare `Relay` in app code.
- **2026-11-24** — Check: `mobile/test/paste_menu_test.dart` is deleted, because the app's own text menu and the Mac's paste channel are gone: the system's own menu shows in the web view, and the page sends a paste's HTML itself.
- **2026-11-24** — Check: the Flutter tests that typed, pasted, right-clicked or triple-clicked in the old editor (in `web_shell_test.dart`, `screens_test.dart` and `mac_shell_test.dart`) are deleted or now check the messages to the page, because the editor page does that work; its own Playwright tests in `mobile/editor-web/test/` check typing, keys, paste placement, triple-click and tables in Chromium.
- **2026-11-24** — Check: `.github/workflows/mobile-ci.yml` gets a step that runs the editor page's Playwright tests before `flutter test`, and `.github/workflows/test.yml` a step that fails when `mobile/assets/editor/source.sha256` does not match the page's source; both add checks and remove none.
- **2026-11-24** — Check: `mobile/editor-web/package.json` is new, with `build`, `test` and `check` scripts and exact versions; it sets no check to pass by itself.
- **2026-11-24** — Assumed: the browser's frame gets the editor page as its own text (`srcdoc`, a Dart copy of the built `index.html` with a `<base>` on the editor's folder, which a test keeps equal), not from `…/editor/index.html`, because the server moves that address to `…/editor/`, which it answers with the app's page; reading the file from the app's assets would ask for the same address.
- **2026-11-24** — Assumed: the note's page keeps one place in the tree in both layouts, and a second `ready` to load counts as a page that started again, so a resize never reloads the frame and a reload by itself gets the note back.
- **2026-11-24** — Assumed: the page host keeps the last `load` with each later file, head, theme, bottom, highlight, placeholder, lock and app keys merged into it, and sends that after a reload, not a reset of the note page's own record of what it sent.
- **2026-11-24** — Assumed: on the Mac, the Edit menu's Cut, Copy and Paste go to the web view as the system's own actions (WebKit lets no script read the clipboard), and Undo, Redo and Select All run in the page, while the note has the keyboard; otherwise they act in the app as before.
- **2026-11-24** — Assumed: the page has the focus only when both its editor and its window have it (`document.hasFocus()`, with the window's focus and blur events), so Find in Note stays open while a person types in it.
- **2026-11-24** — Assumed: the app tells the page its own keys (`appKeys`); the narrow web layout leaves out ⌘F, so the browser's own find opens there.
- **2026-11-24** — Assumed: the web app spec's right-click promise changes to the browser's own menu (a MODIFIED requirement), not removed, because the rest of that requirement still holds.
- **2026-11-24** — Assumed: no reload on Android's render-process-gone, because `webview_flutter_android` 4.13 gives no such event; the design says so. The 200 KB step and the freeing in the background are out of the design; the browser test checks a note over 200 KB is ready and sends its change back in under 3 seconds.
- **2026-11-24** — Assumed: a paste the note can keep nothing of sends nothing to the page, so the words and selection stay as they are.
- **2026-11-24** — Assumed: in the browser the note's page is always drawn and its frame stays clear until `ready`, because Flutter draws no view at zero opacity, so the frame never joined the page.
- **2026-11-24** — Assumed: `pointer_interceptor` 0.10.1+3 (the Flutter team's) under the bars that lie over the words, and the frame takes no click while one of the app's dialogs, sheets, menus or the drawer is open, so each click there goes to the app; the bar buttons still take no focus.
- **2026-11-24** — Check: with the browser's screen reader support on, a click on a bar button still takes the focus from the note, so the next letters go nowhere until a click in the words; not fixed in this change, because Flutter gives each button a `tabindex` and moves the focus to its own view on a click, so no small change keeps the focus in the frame.
- **2026-11-24** — Check: a paste of a heading into the middle of a checklist line makes the line a heading (`Buy ` + *Packing* → `## Buy Packing`); the old editor's paste rule did the same, so it stays.
- **2026-11-24** — Assumed: the left bar counts as over the note for as long as it is shown, not by its open and close calls, because a resize can take it away while open with no close call, and the note then took no click.
- **2026-11-24** — Checkpoint: built and checked here (app tests, editor page tests in Chromium, the web app driven in headless Chromium, the public check); saved for the iPhone check on GitHub's Mac (tasks 8.2 and 9.3), with the Mac and Android checked only by their CI builds.
