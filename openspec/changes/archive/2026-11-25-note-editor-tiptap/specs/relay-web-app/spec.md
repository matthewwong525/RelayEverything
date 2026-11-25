## MODIFIED Requirements

### Requirement: Keyboard and mouse work as on a computer

In the browser the app SHALL take keyboard shortcuts for a new note, search and delete, and the format keys of Notes on a Mac, with ⌘ on a Mac and Ctrl elsewhere: bold, italic, underline, strikethrough (⇧⌘X), highlight (⇧⌘E), Title, Heading, Subheading and Body (⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, and also ⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘0, as the browser keeps some of the others), Monostyled (⇧⌘M), the three lists (⇧⌘7, ⇧⌘8, ⇧⌘9), checklist (⇧⌘L), tick (⇧⌘U), block quote (⌘'), indent (⌘] and ⌘[, and Tab and Shift+Tab in a list), link (⌘K) and table (⌥⌘T). A right-click in a note SHALL show the browser's own menu, with its cut, copy, paste and spell check; the formats are in the app's bar and keys. The app SHALL take files dropped onto an open note. Text SHALL be selectable and copyable.

#### Scenario: Drop a file on a note
- **WHEN** a person drags a PDF from their computer onto the open note
- **THEN** the file is added to the note, as with the paperclip

#### Scenario: A heading from the keyboard in Chrome
- **WHEN** a person on Windows presses Ctrl+Alt+2 on a line
- **THEN** the line shows as a heading, and the browser opens no new tab or window

#### Scenario: A right-click in a note
- **WHEN** a person selects words in an open note and right-clicks them
- **THEN** the browser's own menu shows, and *Copy* puts the words on the clipboard
