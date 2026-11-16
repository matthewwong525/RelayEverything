## MODIFIED Requirements

### Requirement: The Mac app works with a keyboard, a mouse and Finder

The Mac app SHALL have a Mac menu bar with *New Note* (⌘N), *Find* (⌘F) and *Settings* (⌘,), and a *Format* menu with every format item of the note page and its key, the same keys as Notes on a Mac and as the browser takes: bold (⌘B), italic (⌘I), underline (⌘U), strikethrough (⇧⌘X), highlight (⇧⌘E), Title, Heading, Subheading, Body and Monostyled (⇧⌘T, ⇧⌘H, ⇧⌘J, ⇧⌘B, ⇧⌘M), the three lists (⇧⌘7, ⇧⌘8, ⇧⌘9), checklist (⇧⌘L), block quote (⌘'), indent (⌘], ⌘[), link (⌘K) and table (⌥⌘T). A file dropped from Finder onto an open note SHALL be added to that note. A link SHALL open in the person's default browser, and a file on a note SHALL open in its Mac app. Parts that live only on the Relay Everything page, such as webhooks, saved chats and deleting the account, SHALL open that page in the browser.

#### Scenario: New note from the keyboard

- **WHEN** the person presses ⌘N
- **THEN** a new, empty note opens with the cursor in it

#### Scenario: Drop a file

- **WHEN** the person drops a PDF from Finder onto an open note
- **THEN** the PDF is added to that note and syncs with it

#### Scenario: A title from the Format menu

- **WHEN** the person picks *Format* → *Title* in the menu bar, or presses ⇧⌘T
- **THEN** the cursor's line shows as a Title
