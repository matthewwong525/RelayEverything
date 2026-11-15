# Tasks

## 1. The converter

- [x] 1.1 Add `html` (Assumed in design.md, in place of `flutter_quill_delta_from_html`) to `mobile/pubspec.yaml` at the version `pubspec.lock` already holds; `flutter pub get` changes no locked version.
- [x] 1.2 Write `mobile/lib/editor/paste.dart` with `pastedDelta({String? html, required String plain})` as design.md says: HTML → note styles only (header ≤ 3, lists, indent, quote, code block, bold/italic/underline/strike), Google Docs' `font-weight:normal` wrapper unwrapped, a link with its own words as `words (address)`, inline code and embeds dropped; plain text read by `markdownToDelta` with `•`/`◦`/`▪` lines as bullets; empty lines tidied; round-tripped through `deltaToMarkdown`; a lone unstyled line with no final newline. Verify: `mobile/test/paste_test.dart` covers each case in design.md's Testing list and passes.

## 2. Every paste goes through it

- [x] 2.1 In `mobile/lib/screens/note_editor.dart`, add `_paste({html, plain})` (a copy from inside the note pastes back with its styles; else one `replaceText` with `pastedDelta`, caret revealed, links marked) and route the editor's own paste to it through `QuillClipboardConfig.onClipboardPaste`. Verify: a widget test with a mocked clipboard pastes HTML styles, and one *Undo* removes the paste.
- [x] 2.2 Add the `relay/paste` method channel handler, set while the note editor has focus and cleared on blur and dispose, answering `false` with no note focused. Verify: tests in `mobile/test/paste_menu_test.dart` send `paste {html, plain}` as a platform message: a focused note inserts styled words at the cursor and answers `true`; with no note focused it answers `false`; a copy inside the note pastes back with its styles.
- [x] 2.3 Add the web page's `paste` listener (`package:web`, a browser/stub pair like `mobile/lib/web/drops_browser.dart`), routed to `_paste` while the note editor has focus. Verify: `mobile/test/web_imports_test.dart` passes and `flutter build web` (the app's web build command) compiles.
- [x] 2.4 Write `mobile/ios/Runner/RelayPaste.swift`: swizzle `FlutterTextInputView paste:` (fail safe when missing), read plain text and HTML (`public.html`, else Safari's web archive, else RTF/RTFD walked into simple HTML), send `paste` on `relay/paste`, and on `false`/error/no channel insert the plain text read at the start. Register it from `AppDelegate.swift` with the main engine's messenger. Verify: the iOS build compiles in CI; the Dart channel tests above pin the contract.

## 3. Docs

- [x] 3.1 Update `site/src/content/docs/app/your-notes.md` (the *Pasted words come in as plain text* sentence) and `site/src/content/docs/app/on-a-computer.md` to say a paste keeps headings, lists, checklists, quotes, code, and bold, italic, underlined and struck words, reads Markdown, keeps a link's address, and drops colors, fonts and pictures. Verify: `node scripts/product-name.test.mjs` passes.

## 4. Checks

- [x] 4.1 Run `flutter analyze` and `flutter test` in `mobile/`; both pass.
