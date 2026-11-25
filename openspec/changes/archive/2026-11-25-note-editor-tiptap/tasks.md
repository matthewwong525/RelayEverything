# Tasks

## 1. Golden set first

- [x] 1.1 Collect every Markdown input in `mobile/test/markdown_test.dart` and `paste_test.dart` into one golden list of note texts that must write back unchanged; verify it passes against today's super_editor reader and writer before anything moves.

## 2. The editor page

- [x] 2.1 Make `mobile/editor-web/` (exact versions, lock file): Tiptap 3.35.0 core, StarterKit, list, table, highlight and placeholder parts, esbuild writing `index.html`, `editor.js`, `editor.css` and Inter into `mobile/assets/editor/` with `source.sha256`; add the folder to `pubspec.yaml` assets; verify the build runs offline from the lock file and the page names no outside address.
- [x] 2.2 Write the document schema of design decision 2: Title heading, dashed bullet lists, a second paragraph in a list item, the `attachment` atom, the `link` mark with `auto`, the `highlight` mark with `colour`; verify a Playwright test loads one document of each kind and gets it back unchanged from `changed`.
- [x] 2.3 Write the bridge in the page (`load`, `run`, `files`, `paste` in; `ready`, `changed`, `state`, `paste`, `tap`, `open`, `keys` out) on both the JS channel and `postMessage`; verify a test runs each `run` action and checks the `state` that comes back.
- [x] 2.4 Write input rules (`# `, `## `, `### `, `- `, `* `, `1. `, `[] `, `[ ] `, `> `) with Undo giving back the marks; Tab and Shift+Tab on every selected item; triple-click selecting one paragraph; Return in a table cell; the refusal of a file removal in a note from elsewhere; Undo floor at the opened document; verify a browser test for each.
- [x] 2.5 Write `editor.css` from CSS variables, with the values of today's `editor/note_style.dart` and `brand.dart`: even spacing, round checklist circles with the tick motion, `caret-color`, no tap highlight, Reduce Motion; the picture, file row and recording card node views matching `screens/note_blocks.dart`; verify screenshots in light and dark against today's note at the same width.
- [x] 2.6 Add a Node test in `test.yml` that fails when `source.sha256` does not match `mobile/editor-web/`; verify it fails on a changed source file and passes after a build.

## 3. Markdown and paste in Dart

- [x] 3.1 Rewrite the last step of `editor/markdown.dart` as `markdownToDoc` and `docToMarkdown` on the editor's JSON, keeping the line reader, the writer and `plainText`; verify the golden set from 1.1 passes through the new form.
- [x] 3.2 Move table and file lines (`editor/table.dart`, `editor/attachments.dart`) to the new form, with `\|` kept in cells; verify table and file-line round-trip tests pass.
- [x] 3.3 Point `editor/paste.dart`'s output at the new form, as one slice; verify today's paste tests pass, including a numbered list with `Why:` lines and one line with no style joining the line.

## 4. Hosts and the bridge in Dart

- [x] 4.1 Add `webview_flutter` 4.14.1 (exact) and write `lib/editor/web_note/`: `WebNote`, `NoteState`, the native host (`loadFlutterAsset`, JS channel, transparent, navigation refused), the frame host for the web page (checked sender), picked by conditional import; verify unit tests with a fake host for message encoding and the refused navigation.
- [x] 4.2 Write `WebNotePool`: one ready page from app start, one spare, zero opacity until `ready`, reload on a gone page; verify tests that a second note takes the spare and a gone page reloads with the last document.
- [x] 4.3 Add `ios/Runner/RelayWebKeyboard.swift` (no arrow bar; `focus()` raises the keyboard; each WebKit name looked up first), Android focus in `MainActivity.kt`, and any macOS sandbox setting the web view needs; verify the iOS, Android and macOS builds in CI.

## 5. The note page and its bars

- [x] 5.1 Rebuild `screens/note_editor.dart` on `WebNote`: load, autosave on `changed`, empty-note delete, the date and voice card inside the page, bottom padding from the keyboard and bar, new note with the keyboard up, swipe-back strip; verify the note page tests in `screens_test.dart` with `FakeWebNote` in `test/fakes.dart`.
- [x] 5.2 Port `editor/note_commands.dart` and `screens/note_bars.dart` to `NoteState` and `run`, with bar buttons that take no focus, and the Format sheet using `keyboard off`; verify each button's test, lit states included.
- [x] 5.3 Port Find in Note, Undo and Redo, links (`editor/links.dart`: a tap while reading opens the browser) and `editor/shortcuts.dart` with the Mac menu bar and the `keys` message; verify `shortcuts_test.dart` and `mac_shell_test.dart`.
- [x] 5.4 Show Recently Deleted in the same page with `editable: false`; verify its tests and the `recently-deleted` flow.
- [x] 5.5 Review fixes: the browser's frame gets the page as `srcdoc` (no `.html` address), stays in one place on resize and hides itself until ready; a page that starts again gets the note, its files and settings back; the Mac Edit menu acts in the note; Find in Note follows the page's focus; Ctrl+F goes to the browser in the narrow web layout; an empty paste sends nothing; the app's bars, menus and dialogs take their clicks over the frame; verify `web_note_test`, `web_shell_test`, `mac_shell_test`, `screens_test` and the editor's browser tests.

## 6. Files, recordings and tables

- [x] 6.1 Make each attachment's `src` (the web address on the web page; a JPEG at the shown width elsewhere), insert files at the cursor's line from *Attach* and the mic, and route `tap` to open, play, seek and the transcript; send the play position while playing; verify tests for insert, open and play with `FakeRelay`.
- [x] 6.2 Wire the table commands (add, convert, delete) and the table bar state; verify the table tests in `screens_test.dart`.

## 7. Remove the old editor

- [x] 7.1 Remove `super_editor`, `follow_the_leader` and `overlord` from `pubspec.yaml`, delete `editor/note_style.dart` and `editor/system_menu.dart`, and the `relay/clipboard` channel if nothing calls it; verify `grep -r super_editor mobile/lib mobile/test` finds nothing and `paste_menu_test.dart` is rewritten for the system menu.

## 8. Tests, checks and docs

- [x] 8.1 Add the editor's Playwright tests to `mobile-ci.yml` (`npm ci`, the Chromium from Playwright) before `flutter test`; verify the job runs them on a pull request.
- [x] 8.2 Change the iPhone check's note flows (`new-note`, `note-styles`, `paste-menu`, `note-toolbar-tables`, `media-between-words`, `recording-card`, `recently-deleted`, `voice-note`) to find words through the web view's accessibility labels; verify each flow passes on the simulator.
- [x] 8.3 Update [the note editor](../../../wiki/relay-note-editor.md) wiki page (built on Tiptap; why; what to check), `mobile/README.md` (where the code is; how to build the editor page), and `site/src/content/docs/app/on-a-computer.md` and the notes pages with one line on the system's own editing; add any new user-facing file to `scripts/product-name.test.mjs`; verify it passes.

## 9. Final checks

- [x] 9.1 Run `flutter analyze` and `flutter test` in `mobile/`, the editor's Playwright tests, and `node scripts/public-check.mjs`; verify all are clean.
- [x] 9.2 Build the web app and drive a note in headless Chromium: type, bold from the bar, a checklist, a paste, a triple-click, dark mode caret, open time; verify each with a screenshot.
- [x] 9.3 `/save`, then run the iPhone check with video; verify no arrow bar over the keyboard, the keyboard stays up on bar taps, the cursor stays above the bar, a new note opens with the keyboard up, the system menu's *Paste* asks no question, and no white flash in dark mode. Report Android as checked only by its build and the browser tests.
