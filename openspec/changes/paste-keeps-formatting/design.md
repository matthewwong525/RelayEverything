# Design: pasted words keep their formatting

## Context

The note editor is `flutter_quill` 11.6 (`mobile/lib/screens/note_editor.dart`), and a note is stored as Markdown (`mobile/lib/editor/markdown.dart`: `markdownToDelta`, `deltaToMarkdown`). Three paste routes exist today:

1. **The iPhone's own *Paste*** (`IOSSystemContextMenuItemPaste` in `mobile/lib/editor/system_menu.dart`, iOS 16+). The engine's `FlutterTextInputView paste:` reads `UIPasteboard.general.string` and calls `insertText:`, so only plain text arrives. This route asks no *Allow Paste?* question (PR #112) and must keep that.
2. **The editor's own paste** (the drawn menu on Android and older iPhones, and ⌘V/Ctrl+V on a hardware keyboard): `QuillRawEditorState.pasteText` → `QuillController.clipboardPaste`, which already tries HTML through `quill_native_bridge` and `DeltaX.fromHtml`, but inserts every attribute the HTML gives (color, size, link, header 4–6…). `deltaToMarkdown` then drops what Markdown can't hold, so the page and the stored note differ until the note opens again.
3. **The web page** (`main_web.dart`, same `NoteEditor`): the browser pastes plain text into Flutter's hidden text field.

## Goals / Non-Goals

- Goal: one Dart function decides what a paste becomes, for every route, so the page shows exactly what the note stores.
- Goal: the iPhone's own *Paste* keeps asking no question.
- Non-goal: pictures in a paste, tables as grids, a "paste as plain text" item. Undo takes back a paste.

## Decisions

### One converter: `pastedDelta({String? html, required String plain})`

New `mobile/lib/editor/paste.dart`, pure Dart, unit-tested:

- **HTML present and holds words** → a small reader over `package:html` (already in `pubspec.lock` through `flutter_quill`; added to `pubspec.yaml` as a direct dependency at the locked version) walks the page and keeps only the note's styles: `header` (clamped to 1–3), `list` (`bullet`, `ordered`, `checked`, `unchecked`; keep `dashed` if present), `indent` (≤ 8), `blockquote`, `code-block`, and inline `bold`, `italic`, `underline`, `strike`. Inline `code` becomes plain words. A `link` whose words differ from its address becomes `words (address)`. Embeds go.
  - Google Docs wraps the whole copy in `<b style="font-weight:normal" id="docs-internal-guid-…">`: a weight under 600 ends bold, so the paste is not all bold.
- **Plain text only** → `markdownToDelta(plain)`, the same reader a stored note uses, so `## Plan`, `- [ ] x`, `**bold**` become styles and `2020. was a year` or `snake_case` stay words. Lines that start with `• `, `◦ ` or `▪ ` become bullet items first.
- **Tidy, both routes:** turn `\r\n` into `\n`; join runs of empty lines into one; drop empty lines at the start and end.
- **Round-trip:** the result is `markdownToDelta(deltaToMarkdown(normalized))`, so what the page shows is what the note stores.
- **One unstyled line:** drop the final unstyled `\n`, so `oat` joins the line `Buy milk` and does not split it or restyle it (`pasteChange`, beside `pastedDelta`).

### One inserter in the note editor

`NoteEditorState._paste({String? html, required String plain})`:

- If `plain == _controller.pastePlainText` and the editor holds a copy from inside the note, paste with `replaceTextWithEmbeds`, which puts the copied styles back, as `flutter_quill` does now.
- Else `_controller.replaceText(sel.start, sel.end - sel.start, pastedDelta(...), collapsed after the paste)` once, so one *Undo* takes it back, then reveal the caret and run the link marking the editor already runs after a change (`withLinks`).

Routes into it:

- **Editor's own paste** → `QuillControllerConfig(clipboardConfig: QuillClipboardConfig(onClipboardPaste: …))`; the handler reads HTML through `ClipboardServiceProvider.instance.getHtmlText()` (falling back to `getHtmlFile()`) and plain through `Clipboard.getData`, calls `_paste`, and returns `true`.
- **iPhone's own *Paste*** → a method channel `relay/paste`, method `paste`, args `{html, plain}`, result `bool` (handled). The note editor sets the handler while its focus node has focus and clears it on blur and dispose; with no note editor focused the handler answers `false`.
- **Web** → a `paste` listener on `document` (`package:web`, in a `_browser.dart`/stub pair as `drops_browser.dart` does): while the note editor has focus, read `clipboardData.getData('text/html')` and `'text/plain'`, `preventDefault()`, and call `_paste`. `test/web_imports_test.dart` must still pass.

### The iPhone side: `RelayPaste.swift`

Swizzle `paste:` on the engine's `FlutterTextInputView` class (found with `NSClassFromString`; if the class or method is missing, do nothing, and the plain paste stays). The new `paste:` runs inside the system's paste action, so its pasteboard reads ask no question:

1. Read `plain = UIPasteboard.general.string`.
2. Read HTML: `public.html`; else the `WebMainResource` → `WebResourceData` of an `Apple Web Archive pasteboard type` plist (Safari); else `public.rtf` / `com.apple.flat-rtfd` (Apple Notes, Pages) turned into simple HTML by walking the `NSAttributedString`: bold and italic font traits, underline, strikethrough, links, paragraphs, and `NSTextList` items as `<ul>`/`<ol>` `<li>`. Not `NSAttributedString`'s own HTML export: it puts styles in CSS classes the Dart converter does not read.
3. Send `paste {html, plain}` on `relay/paste` with the main engine's messenger (kept from `didInitializeImplicitFlutterEngine`). On `true`, done. On `false`, an error, or no channel, call `insertText:` on the view with the `plain` read in step 1 (weakly held), which is what the engine's own `paste:` does, with no second pasteboard read.

Messages from the platform reach Dart in order, so the paste lands before any later keystroke.

## Risks / Trade-offs

- **Swizzling an engine class** can break on a Flutter upgrade that renames it. Mitigation: the lookup fails safe to today's plain paste, and a Dart test pins the channel contract. The iOS build in CI compiles the Swift file; no Mac is on this host.
- **HTML from some apps is messy** (Word, Outlook). The converter keeps only known styles, so the worst case is plain words with fewer styles, never stray colors or sizes.
- **A link's address after its words** can be long. Trade-off accepted: no address is lost, and the note stays plain Markdown for the server, Claude and webhooks.

## Testing

- `mobile/test/paste_test.dart`: `pastedDelta` with saved HTML from a web page (headings, lists, bold), Notion (checklist `data-checked`/`checkbox`), Google Docs (the `font-weight:normal` wrapper), ChatGPT HTML, an Apple-Notes-like RTF-made HTML, colors/sizes dropped, h4→h3, link with words, Markdown plain text, `•` lines, a single unstyled line, blank-line tidy, round-trip equality.
- `mobile/test/paste_menu_test.dart`: a `relay/paste` platform message into a focused note inserts styled words at the cursor and returns `true`; with no note focused it returns `false`; one *Undo* removes the paste; a copy inside the note pastes back with its styles; `onClipboardPaste` with a mocked clipboard pastes HTML styles.

## Decision log

- **2026-11-15** — Assumed: every paste route gets the formatting (iPhone menu, Android, keyboard keys, web page), because the person said "if it pastes from anywhere".
- **2026-11-15** — Assumed: a link with its own words pastes as `words (address)`, because a note is plain Markdown with no hidden link target, and dropping the address loses it.
- **2026-11-15** — Assumed: pasted plain text is read as Markdown, as Notion does, because ChatGPT and Claude copy Markdown and a stored note reads its own `**` marks as bold on the next open anyway.
- **2026-11-15** — Assumed: no *Paste as plain text* item, because *Undo* takes a paste back and the menu stays the iPhone's own.
- **2026-11-15** — Assumed: the HTML is read by our own walker over `package:html`, not `HtmlToDelta`, because a probe of `flutter_quill_delta_from_html` 1.5.3 joined `<p>one</p><p>two</p>` into `onetwo`, read Google Docs' whole copy as one bold line, and joined a `<pre>` block's lines. `html` 0.15.7 is the locked version, so no locked version changes.
- **2026-11-15** — Assumed: `pasteChange` keeps the cursor line's style beyond the one-line case: an unstyled last line joins the words after the cursor; a paste at a line's end gives that line the last pasted line's style, so lines pasted into a new note's empty Title line do not make the last one a Title; the words before the cursor keep their line's style when the first pasted line has none.
- **2026-11-15** — Checkpoint: built and reviewed (no findings); local analyze and 842 tests pass; saved so CI's iOS build compiles `RelayPaste.swift` (task 2.4).
