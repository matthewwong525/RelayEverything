## MODIFIED Requirements

### Requirement: The layout fits the window

In a window at least 1,000 px wide the app SHALL show three panes: folders, the open folder's notes, and the open note. Between 700 and 1,000 px it SHALL show the notes and the open note, with the folders in a menu. Under 700 px it SHALL show the phone layout, one page at a time. A change of window size SHALL keep the open note and any words not yet saved. In the two wide layouts, one bar SHALL run along the top with the new-note button, *Text styles*, *Checklist*, *Table* and *Attach*, Share and search at its right end, and nothing SHALL sit at the bottom of the window. *Text styles* SHALL open a menu under its button, as Notes on a Mac has it: bold, italic, underline, strikethrough, the highlight pen and the colour at the top; then Title, Heading, Subheading, Body, Monostyled, Bulleted List, Dashed List and Numbered List, each in its own look with a ✓ at the current one; then Block Quote. A pick SHALL close the menu and leave the cursor in the note.

#### Scenario: A wide window
- **WHEN** a person opens the page in a 1,440 px wide window and taps a note
- **THEN** the note opens in the right pane, and the folders and the list stay in view

#### Scenario: Search from the top bar
- **WHEN** a person types a word in the search field at the top right
- **THEN** the list shows only the notes with that word, and the open note stays open

#### Scenario: The window gets narrow while a note is open
- **WHEN** a person types in a note and narrows the window to 600 px
- **THEN** the same note stays open as a full page, with every word typed

#### Scenario: A heading from the Aa menu
- **WHEN** a person clicks *Text styles* and then *Heading*
- **THEN** the menu closes, the cursor's line shows as a heading, and typing goes on in the note

### Requirement: Keyboard and mouse work as on a computer

In the browser the app SHALL take keyboard shortcuts for a new note, search and delete, and the format keys of Notes on a Mac, with ⌘ on a Mac and Ctrl elsewhere: bold, italic, underline, strikethrough (⇧⌘X), highlight (⇧⌘E), Title, Heading, Subheading and Body (⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, and also ⌥⌘1, ⌥⌘2, ⌥⌘3, ⌥⌘0, as the browser keeps some of the others), Monostyled (⇧⌘M), the three lists (⇧⌘7, ⇧⌘8, ⇧⌘9), checklist (⇧⌘L), tick (⇧⌘U), block quote (⌘'), indent (⌘] and ⌘[, and Tab and Shift+Tab in a list), link (⌘K) and table (⌥⌘T). A right-click on selected words SHALL offer *Bold*, *Italic*, *Underline*, *Strikethrough*, *Highlight* and *Link…* with the usual cut, copy and paste. The app SHALL take files dropped onto an open note. Text SHALL be selectable and copyable.

#### Scenario: Drop a file on a note
- **WHEN** a person drags a PDF from their computer onto the open note
- **THEN** the file is added to the note, as with the paperclip

#### Scenario: A heading from the keyboard in Chrome
- **WHEN** a person on Windows presses Ctrl+Alt+2 on a line
- **THEN** the line shows as a heading, and the browser opens no new tab or window
