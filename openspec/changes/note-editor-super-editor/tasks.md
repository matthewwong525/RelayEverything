# Tasks

## 1. Markdown golden set (before the swap)

- [x] 1.1 Collect every Markdown input in `mobile/test/markdown_test.dart` and `paste_test.dart` into a golden list of note texts that must write back unchanged; verify the list runs green against today's Quill reader and writer.

## 2. Package swap

- [x] 2.1 In `mobile/pubspec.yaml` remove `flutter_quill`, add `super_editor: 0.3.0-dev.52` (exact); verify `flutter pub get` resolves and `pubspec.lock` holds no `flutter_quill`.

## 3. Document model and Markdown

- [x] 3.1 Rewrite `editor/markdown.dart` as `markdownToDocument` and `documentToMarkdown` per the design's mapping, with `HighlightAttribution`, dashed metadata, Title metadata, and continuation lines inside list items; verify the golden set from 1.1 passes and new tests for a continuation line and a dashed sub-list pass in `markdown_test.dart`.
- [x] 3.2 Add `NoteTableNode` and `AttachmentNode` (`editor/table.dart`, `editor/attachments.dart`) with their Markdown lines; verify table and file-line round-trip tests pass.

## 4. Paste

- [x] 4.1 Port `editor/paste.dart` to produce document nodes and insert them as one undoable change; verify today's paste tests pass on the new model.
- [x] 4.2 Add relative indent and continuation lines to the plain-text reader; verify new tests with made-up words: an indented numbered list under a label pastes as 1, 2, 3 with each `Why:` line under its item, and a real sub-list stays a sub-list.

## 5. The note page

- [x] 5.1 Rebuild `screens/note_editor.dart` on `SuperEditor` with the stylesheet in `editor/note_style.dart` (even spacing), checklist circle, dash and number builders, table and file builders, autosave, empty-note delete, cursor kept above the bar, Find in Note and Undo/Redo; verify the editor tests in `test/screens_test.dart` pass, rewritten only where they named Quill.
- [x] 5.2 Add the triple-tap delegate that selects one line between line breaks; verify widget tests: a mouse triple-click on an item selects its words and not its `Why:` line, a touch triple-tap does the same, and a double-click still selects one word.
- [x] 5.3 Port `screens/note_bars.dart` (keyboard bar, selection bar, Format sheet) to `NoteCommands`; verify each button's test in `screens_test.dart`, lit states included.
- [x] 5.4 Set typed-mark reactions (`# `, `## `, `### `, `- `, `* `, `1. `, `[] `, `> `), with Undo giving back the marks, and no dash or link conversion; verify tests for each mark and its Undo.
- [x] 5.5 Port `editor/system_menu.dart` and `editor/shortcuts.dart`; remove `editor/magnifier.dart`; verify `paste_menu_test.dart`, `shortcuts_test.dart` and `mac_shell_test.dart` pass.
- [x] 5.6 Move `screens/recently_deleted.dart` to a read-only `SuperReader` and drop Quill from `screens/timeline.dart`; verify their tests pass and `grep -r flutter_quill mobile/` finds nothing.
- [x] 5.7 Check the web page path in `web_shell_test.dart` (type, paste, triple-click); verify it passes.
- [x] 5.8 Fix the review's findings: a quiet change in a note from elsewhere keeps out a gone file; iPhone, iPad and Android answer `relay/clipboard`; iOS 15's drawn menu has Select All; a `<br>` in a pasted item stays in the item; blank lines inside an item read back in it; verify new tests in `screens_test.dart`, `paste_test.dart`, `paste_menu_test.dart`, `markdown_test.dart` and `web_shell_test.dart` (even spacing, web paste and triple-click, Android triple tap) pass.

## 6. Docs

- [x] 6.1 Add one line on triple-click and pasted lists to the website's notes page in `site/`, and update the phone app's wiki page if it names flutter_quill; verify `scripts/product-name.test.mjs` passes.

## 7. Checks

- [x] 7.1 Run `flutter analyze` and `flutter test` in `mobile/`; verify both are clean.
- [ ] 7.2 Run the iPhone simulator check (`mobile/device-check`) with a native *Paste* from another app; verify no *Allow Paste?* question shows and the pasted list keeps its numbers.
- [x] 7.3 `/save` and open the preview builds; verify on the Mac app and the web page that a triple-click selects one line, a pasted plan keeps 1, 2, 3 with its `Why:` lines, and the spacing is even.
