# Pasted words keep their formatting

**Status:** built; waiting for the iOS build in CI to compile the iPhone paste
**Branch:** nervous-catfish
**Open questions:** none

## Why

Today a paste puts in plain text only. A list, a heading or bold words copied from a web page, Notion, Google Docs or a chat with an AI come in flat, and Markdown from ChatGPT or Claude shows its `**` and `#` marks. The person wants a paste to look right at once, as in Notion.

## What Changes

- **A paste keeps the formatting the note can show.** Words copied from a web page, Notion, Google Docs, Apple Notes, Word or an email come in with their headings, bullet and numbered lists, checklists, quotes, code blocks, and bold, italic, underlined and struck-through words. Colors, fonts, sizes and pictures go: the pasted words take the note's own look.
  No real picture: the screen test cannot put a web page's formatting on the phone's clipboard, so these cards draw the result.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Copied from a web page</span>
      <h3>Trip to Lisbon</h3>
      <div>Things to <b>book</b> first:</div>
      <div>• Flights</div>
      <div>• Hotel near <i>Alfama</i></div>
      <div>1. Pack light</div>
    </div>
    <div class="card col gap phone">
      <span class="muted">Pasted into a note, before</span>
      <div>Trip to Lisbon</div>
      <div>Things to book first:</div>
      <div>Flights</div>
      <div>Hotel near Alfama</div>
      <div>Pack light</div>
    </div>
    <div class="card col gap phone">
      <span class="muted">Pasted into a note, after</span>
      <h3>Trip to Lisbon</h3>
      <div>Things to <b>book</b> first:</div>
      <div>• Flights</div>
      <div>• Hotel near <i>Alfama</i></div>
      <div>1. Pack light</div>
    </div>
  </div>
  ```

- **Pasted Markdown turns into formatting.** Words copied from ChatGPT, Claude or a text file, such as `## Plan`, `- milk` or `**now**`, come in as a heading, a list item and bold words, not as marks.
  No real picture: the screen test cannot put a web page's formatting on the phone's clipboard, so these cards draw the result.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Copied</span>
      <div>## Plan</div>
      <div>- [ ] Call the bank</div>
      <div>- Buy **oat** milk</div>
    </div>
    <div class="card col gap phone">
      <span class="muted">Pasted into a note</span>
      <h3>Plan</h3>
      <div>○ Call the bank</div>
      <div>– Buy <b>oat</b> milk</div>
    </div>
  </div>
  ```

- **A link keeps its address.** A link whose words are not its address, such as *the menu*, comes in as `the menu (https://…)`, so the address stays and shows as a link you can tap.

- **It works everywhere you paste.** On an iPhone, the iPhone's own *Paste* still asks no *Allow Paste?* question. It works the same on Android, with a keyboard's ⌘V or Ctrl+V, and on the Relay Everything web page. *Undo* takes back the whole paste in one step. A copy inside a note pastes back with its styles, as before.

## What the build needs

Nothing from you. The build uses the editor's own parts and no new service or key.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-note-editing`: the text menu's *Paste* keeps the formatting the note can show, and pasted Markdown becomes formatting, in place of plain text.

## Impact

- `mobile/lib/editor/paste.dart` (new): turns pasted HTML or plain text into the note's own styles.
- `mobile/lib/screens/note_editor.dart`: routes every paste through it (`QuillClipboardConfig.onClipboardPaste`, the iPhone channel, the browser's paste event).
- `mobile/ios/Runner/RelayPaste.swift` (new) and `AppDelegate.swift`: the iPhone's own *Paste* hands the clipboard's HTML (or RTF, or a web archive) and plain text to the app, still with no *Allow Paste?* question.
- `mobile/lib/web/`: a browser `paste` listener for the web page.
- `site/src/content/docs/app/your-notes.md` and `on-a-computer.md`: the paste text.
- Tests: `mobile/test/paste_test.dart` (new), `mobile/test/paste_menu_test.dart`.
