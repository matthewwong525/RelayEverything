# Design

## Context

The note editor (`mobile/lib/screens/note_editor.dart`) is a `QuillEditor` on a Quill `Document`. Notes are stored as Markdown: `editor/markdown.dart` turns Markdown into a Quill `Delta` and back, and owns our dialect (Title first line, dashed lists `- `, bullets `* `, checklists `- [ ]`, `<u>`, `<mark class>`, Markdown tables, `![name](attachment:<id>)` file lines). `editor/paste.dart` reads a paste (HTML or plain text) into lines, tidies them, and goes through Markdown so a paste equals what is stored. Tables (`table.dart`) and files (`attachments.dart`) are Quill embeds with our own widgets. The iPhone's own menu (`system_menu.dart`), the magnifier, Mac keys (`shortcuts.dart`), the bars (`note_bars.dart`) and Find in Note call Quill's controller.

`super_editor` 0.3.0-dev.52 resolves with the app's packages only when `flutter_quill` is gone: both pin different `dart_quill_delta` majors. See proposal.md for why we move.

## Goals / Non-Goals

**Goals:**
- Same stored Markdown, byte for byte, for every note a person did not change.
- Every requirement in `relay-note-editing`, `relay-note-tables`, `relay-attachments`, `relay-notes-screen` and `relay-voice-notes` that the editor serves keeps passing, plus the three new ones.
- One code path on iPhone, Android, Mac and web.

**Non-Goals:**
- super_editor's own Markdown reader and writer, its `/` menu, drag handles, AI tools, chat widgets.
- A new look: the note keeps the Apple Notes look of [Matthew's page](../../../knowledge/people/matthew-wong.md).

## Decisions

### 1. Our Markdown stays the source of truth
`editor/markdown.dart` becomes `markdownToDocument(text, {title, files}) → MutableDocument` and `documentToMarkdown(Document) → String`, reusing today's line reader and writer, with the Delta step removed. Mapping:

| Markdown | super_editor node |
|---|---|
| first line (Title) | `ParagraphNode`, `blockType: header1`, metadata `title: true` |
| `#`/`##`/`###` | `ParagraphNode` header1–3 |
| body, `> ` quote, fenced code | `ParagraphNode` paragraph / blockquote / code |
| `* ` bullet, `- ` dashed, `1. ` | `ListItemNode` unordered (metadata `dashed`) / ordered, with `indent` |
| `- [ ]`, `- [x]` | `TaskNode` with `indent` |
| Markdown table | `NoteTableNode extends BlockNode` (our cells) |
| `![name](attachment:id)` | `AttachmentNode extends BlockNode` |
| `**`, `*`, `~~`, `<u>`, `<mark class>`, `[w](a)`, `` ` `` | attributions: bold, italics, strikethrough, underline, `HighlightAttribution(colour)`, `LinkAttribution`, code |

A line indented under a list item (more spaces than the item's mark) joins that item's text after a `\n` inside the node, and is written back as a line indented to the item's text. **Why not super_editor's Markdown package:** it caps super_editor below dev.40 and knows none of our marks. **Why keep Markdown:** server, AI connector, webhooks and old notes read it (`relay-note-editing` *Styles stay readable as plain text*).

Proof: today's `test/markdown_test.dart` fixtures become a golden set; each must read and write back to the same text before the editor is swapped in.

### 2. Paste reads into the same line model, with two fixes
`paste.dart` keeps its HTML reader and tidy step, and ends in `markdownToDocument` → nodes inserted at the selection as one undoable transaction (`InsertNodesRequest`/`PasteStructuredContentEditorRequest` inside one `editor.execute` with one history entry). Plain-text fixes in `_plainMarkdown`:
- **Relative indent:** the indent of the first list line of a run (≤ 3 spaces, no list above it) becomes level 0; deeper lines count levels from it (2 spaces or a tab a level, as now).
- **Continuation lines:** a non-blank, non-list line indented at least to the text start of the list item above it belongs to that item. The ordered counter does not reset across it.
Test fixtures use made-up words only: the repo is public, so never a person's or a customer's name from the pasted sample.

### 3. Triple-click and triple-tap select a line
super_editor already counts taps on mouse (`document_gestures_mouse.dart`) and iOS/Android touch. We pass a `ContentTapDelegate` whose `onTripleTap` finds the text node at the tap, selects from the `\n` before the offset to the next `\n` (or the node's ends), and returns `TapHandlingInstruction.halt`. Non-text blocks return `continueHandling` so a table or file block is selected whole, as super_editor does. Double-click keeps super_editor's word selection.

### 4. Even spacing is one stylesheet
One `Stylesheet` (in a new `editor/note_style.dart`, replacing `noteStyles`) sets every text block's padding to the same top value (body line gap) and zero bottom, headings one larger fixed top, and line height 1.35 inside a block, so a `\n` line inside an item takes the same space as a new block. Empty paragraphs keep their height as the one gap. Phone, Mac and web share it.

### 5. Parts of the page, mapped
- **Checklist circle, dash, numbers:** custom `ComponentBuilder`s for `TaskNode` and `ListItemNode` draw today's `CupertinoIcons` circle and `–` (from `_leading`).
- **Tables and files:** `NoteTableComponentBuilder` hosts today's table widget; `AttachmentComponentBuilder` hosts today's photo, file row and recording card.
- **Bars and Format sheet:** `note_bars.dart` calls a small `NoteCommands` class (bold, heading, list, indent, link, highlight) that issues super_editor requests; the bar's lit state reads attributions at the selection.
- **Typed marks:** keep `HeaderConversionReaction`, list and quote reactions; add a `[] ` task reaction; map `- ` to dashed and `* ` to bullet; drop `DashConversionReaction`, `LinkifyReaction` (we link on save as now) and `ImageUrlConversionReaction`. Undo after a conversion gives back the marks (one history entry before the reaction).
- **iPhone menu:** `system_menu.dart` keeps Flutter's `SystemContextMenu` with our custom Cut/Copy/Select All and the native Paste; it is shown through super_editor's `iOSToolbarBuilder`, and native Paste reaches our paste handler through the IME client's paste action, so no *Allow Paste?* shows.
- **Magnifier:** super_editor's iOS magnifier, styled; `magnifier.dart` goes.
- **Mac keys:** `shortcuts.dart` maps to `keyboardActions` on `SuperEditor`.
- **Undo/Redo:** super_editor's history; the opening document is the floor (history cleared after load).
- **Find in Note:** select the match with `ChangeSelectionRequest` and scroll it into view, as now.
- **Cursor above the floating bar:** `SuperEditor`'s scroll controller with the bar's height as bottom padding in `KeyboardScaffoldSafeArea`.
- **Recently Deleted and the list preview:** a read-only `SuperReader` with the same stylesheet; `timeline.dart` reads plain text from Markdown, no editor.

## Risks / Trade-offs

- [super_editor is a pre-release] → pin `0.3.0-dev.52` exactly; any later update is its own change.
- [Native iPhone Paste may raise *Allow Paste?* through a new path] → the iPhone simulator check (`mobile/device-check`) pastes from another app and fails on the question, as the native-paste-menu change did.
- [Web IME and Flutter web text input differ] → `web_shell_test.dart` plus a manual type, paste and triple-click on the preview page.
- [A Markdown round trip drifts for old notes] → the golden set in Decision 1 must pass first; an unchanged note is never re-sent.
- [The swap is all at once] → one branch; nothing goes live until the preview passes on phone, Mac and web.
- [super_editor ships `flutter_test` and `mockito` as normal dependencies] → app size checked on the release build; tree shaking drops unused code.

## Migration Plan

No data moves. Ship as one change; roll back by reverting it, which restores flutter_quill with the same stored text.
