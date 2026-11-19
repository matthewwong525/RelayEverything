# Design

## Context

The note editor is super_editor (0.3.0-dev.52, pinned). Two of its defaults are wrong for us on a computer.

## Decisions

- **Cursor colour.** `SuperEditor.documentOverlayBuilders` defaults to `defaultSuperEditorDocumentOverlayBuilders`, whose `DefaultCaretOverlayBuilder` draws `CaretStyle(width: 2, color: Colors.black)`. `NoteEditor` passes the default list with that builder swapped for one whose colour is `Theme.of(context).colorScheme.onSurface` (the brand's ink). The phone's own caret and handles come from the iOS and Android controls scopes and do not change.
- **Tab with a selection.** super_editor's `tabToIndentListItem` and `shiftTabToUnIndentListItem` act only on the selection's extent node. `_noteKeys` now catches Tab with an expanded selection (no ⌘, Ctrl or Alt) and calls `NoteCommands(_editing).indent(!shift)`, the command the Format sheet's indent buttons use, which moves every selected line. A collapsed selection keeps the editor's own Tab.

## Risks

- A future super_editor that renames `DefaultCaretOverlayBuilder` breaks the build, not the behaviour: the version is pinned.
