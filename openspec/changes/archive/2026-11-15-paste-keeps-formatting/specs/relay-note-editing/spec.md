## MODIFIED Requirements

### Requirement: The text menu is the iPhone's own

While the person edits a note on an iPhone that can show the system text menu (iOS 16 and later), a hold, a selection, or a tap on the cursor SHALL show the iPhone's own text menu, with the standard items that fit the selection: *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Search Web* and *Share*. A tap on *Paste* SHALL put in the words from the clipboard at the cursor, with the formatting the note can show (see *A paste keeps its formatting*), with no *Allow Paste?* question, also for words copied in another app. A tap on the blinking cursor SHALL open the menu, and a second tap SHALL close it; a tap anywhere else SHALL move the cursor there, as before. While the person drags the cursor or a selection handle, a magnifier SHALL show the words under the finger. Where the iPhone's own menu can't show (an older iPhone or Android), the app SHALL show its own menu with the same actions, and the browser SHALL keep the browser's own menu.

#### Scenario: Paste words from another app

- **WHEN** the person copies `Buy oat milk` in Safari, opens a note, and taps *Paste* in the menu after a hold in the words
- **THEN** `Buy oat milk` is in the note at the cursor, in the note's style, and no *Allow Paste?* question showed

#### Scenario: Tap the cursor to open the menu

- **WHEN** the person types in a note and taps on the blinking cursor
- **THEN** the iPhone's own menu shows *Paste* above the cursor, and a second tap on the cursor closes it

## ADDED Requirements

### Requirement: A paste keeps its formatting

A paste into a note SHALL keep each style the note can show: headings (a level past 3 becomes level 3), bullet, dashed, numbered and checklist items with their indent, quotes, code blocks, and bold, italic, underlined and struck-through words. It SHALL drop colors, fonts, sizes, backgrounds, alignment, pictures and other styles the note can't show, so the pasted words take the note's own look. Pasted plain text SHALL be read as Markdown, as a note's own words are read, so `## Plan` pastes as a heading and `**now**` as bold. A link whose words differ from its address SHALL paste as its words followed by its address in brackets. Runs of empty lines SHALL become one, and empty lines at the start and end SHALL go. A paste of one line with no line style SHALL join the line at the cursor. The pasted note SHALL be stored as the Markdown the page shows, so it opens the same again. This SHALL hold for the iPhone's own *Paste*, the app's own menu, a keyboard's paste keys, and the Relay Everything web page. A copy from inside a note SHALL paste back with its styles. One *Undo* SHALL take back the whole paste.

#### Scenario: Paste a list from a web page

- **WHEN** the person copies a heading, a sentence with a bold word, and a bullet list from a web page, and pastes them into a note
- **THEN** the note shows the heading, the bold word, and the bullet items, in the note's own font and colors

#### Scenario: Paste Markdown from a chat

- **WHEN** the person copies `## Plan`, `- [ ] Call the bank` and `- Buy **oat** milk` as plain text and pastes them
- **THEN** the note shows the heading *Plan*, an open checklist item *Call the bank*, and a dashed item *Buy oat milk* with *oat* in bold

#### Scenario: Paste a link with its own words

- **WHEN** the person pastes a link whose words are `the menu` and whose address is `https://example.com/menu`
- **THEN** the note shows `the menu (https://example.com/menu)`, with the address as a link

#### Scenario: Paste a few words into a line

- **WHEN** the person pastes `oat` in the middle of the line `Buy milk`
- **THEN** the line reads `Buy oat milk` and keeps its own style

#### Scenario: Undo a paste

- **WHEN** the person pastes a formatted list and taps *Undo*
- **THEN** the whole pasted list goes in one step
