# The note editor

The note editor is the page where a person writes a note, on the iPhone, the Mac app and the web page. It is built on super_editor, and this page gives what is not clear from the code: why super_editor, what it changes, and what to check before a change. Up: [the wiki](README.md).

## Why super_editor, not flutter_quill

- **Until 2026-11-19 the editor was flutter_quill.** It knows only single and double clicks, so a triple-click could not select a line, and each fix fought the editor.
- **super_editor is an editor made of blocks, as Notion is.** The move ([PR #155](https://github.com/matthewwong525/RelayEverything/pull/155)) gave a triple-click that selects one line, pasted lists that keep their numbers, and even spacing between lines. The plan is in [the archive](../openspec/changes/archive/2026-11-19-note-editor-super-editor/proposal.md), and what shipped is in [the note editing spec](../openspec/specs/relay-note-editing/spec.md).
- **Notes stay the same Markdown.** The server, AI apps and webhooks read the same text as before the move.
- **Two flutter_quill workarounds are gone**: the custom Cut, Copy and Select All of the old text menu, and the caret reveal after each frame. Read the super_editor code before you bring either back.

## Where the code is

- [`mobile/lib/screens/note_editor.dart`](../mobile/lib/screens/note_editor.dart): the note page, its keys, its caret and its bars.
- [`mobile/lib/editor/`](../mobile/lib/editor/): the document and Undo (`note_editing.dart`), Markdown (`markdown.dart`), paste (`paste.dart`), tables (`table.dart`), commands such as indent (`note_commands.dart`) and the text menus (`system_menu.dart`). [The phone app's README](../mobile/README.md#where-the-code-is) gives each file.

## What super_editor does not do for you

- **Tab moves only the selection's last line in super_editor.** The note catches Tab and Shift+Tab and moves every selected line (`NoteCommands.indent`). With no selection, Tab moves the line with the cursor.
- **The computer caret is black by default**, so a dark page hides it. The note draws the caret in the text colour (`onSurface`). The phone keeps its own caret and handles.
- **On an iPhone, a hold on words selects them.** A paste over a selection can look unchanged. To get the text menu at a cursor, tap the words, then tap the cursor again: [the iPhone check's tour](development/device-check-tour.md) does this.

## Before you merge a change to the editor

Check these by hand, because the tests did not catch them after the move:

- **Dark mode**: the caret shows on the web page and the Mac app.
- **Tab and Shift+Tab on several selected lines**: all of them move.
- **A triple-tap on a real iPhone and a triple-click in the Mac app**: the iPhone check taps too slowly to count as three, so only a real device shows it.
