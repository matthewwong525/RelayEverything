# relay-note-editing Specification

## Purpose
Lets a person write and change a note in place on the phone, with Apple Notes text styles, lists and checklists, and keeps a sent note's copies on the server and webhooks current.

## Requirements

### Requirement: A note edits in place

A tap on a note's words SHALL put the cursor there and bring up the keyboard, on the same page that shows the note. A new note SHALL open on that page with the keyboard up and its first line styled as a title. Each change SHALL be kept on the phone within two seconds of a pause in typing, and when the person leaves the page, with no *Save* button. A note left with no words and no files SHALL be deleted when the person leaves it, as Apple Notes does, with *Undo*: a note never sent and with no upload waiting SHALL be deleted on the phone only, with any change of it still waiting, so it is never sent; a sent note, or one whose first upload waits or is on its way, SHALL be deleted everywhere, as a delete from the ⋯ menu is. A voice note left with no words SHALL keep its recording. A voice note's words SHALL be editable, and its recording SHALL stay unchanged.

#### Scenario: Fix a word and leave
- **WHEN** the person opens a note, taps a word, types a fix and taps back
- **THEN** the list shows the note with the fix, and the fix is still there after the app restarts

#### Scenario: An empty new note
- **WHEN** the person opens a new note and leaves without typing or adding a file
- **THEN** no note is added to the list

#### Scenario: An emptied note
- **WHEN** the person deletes every word of a note that has no files or recording, and leaves
- **THEN** the note is gone from the list with *Undo*, and when the *Undo* time ends a sent copy is deleted from the page and webhooks get `note.deleted`

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float close above it, about 6 points over its top, as wide as the screen less a margin. It SHALL show *Text styles*, *Checklist*, *Table*, *Attach* and, on a phone, *Record* first, and a sideways swipe SHALL show *Bulleted list*, *Numbered list*, *Link*, *Indent less*, *Indent more* and *Hide keyboard*; part of the next button SHALL show at the edge while more are out of view. While words are selected, the bar SHALL show bold, italic, underline, strikethrough, *Highlight*, *Link* and *Lists* in its place, each lit when the selected words have it, and SHALL change back when the selection goes. The bar SHALL show no drawing and no AI tools. The top SHALL show back, share, ⋯ and a done button that closes the keyboard. The page SHALL keep the cursor in view above the floating tool bar, never under it and never under the top edge, when the person taps into the note, as they type, and when the cursor moves, such as by Undo. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach*, on a phone *Record*, and a compose button that opens a new note. *Record* SHALL record into the open note, as the voice notes requirements say. The ⋯ menu SHALL offer *Pin Note* or *Unpin Note*, *Find in Note* on a phone, *Copy*, and *Delete*. It SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with *Record* and the compose button shows

#### Scenario: No mic on the web page
- **WHEN** the person opens a note on the Relay Everything web page or in the Mac app
- **THEN** the bars show no *Record* button

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

#### Scenario: Typing at the end of a long note
- **WHEN** the person taps at the end of a note longer than the screen and types a line
- **THEN** the page scrolls so the line with the cursor shows above the floating tool bar

#### Scenario: Swipe the bar for more tools
- **WHEN** the person swipes the bar over the keyboard to the left
- **THEN** *Numbered list*, *Link* and *Indent more* come into view, and the keyboard stays up

#### Scenario: Select words
- **WHEN** the person selects a bold word
- **THEN** the bar shows the style tools with bold lit, and when the person taps elsewhere in the note the bar shows *Text styles* first again

### Requirement: Text styles, lists and checklists

*Text styles* SHALL open a Format sheet in the keyboard's place with Title, Heading, Subheading, Body and Monostyled for a line, each shown in its own look and the current one filled; bold, italic, underline and strikethrough for selected words; a highlight pen and a colour choice of purple, pink, orange, green and blue; bulleted, dashed and numbered lists; indent in and out; and block quote. A checklist line SHALL show a circle that one tap ticks or unticks, also while the keyboard is down. Return on an empty list or checklist line SHALL end the list. At the start of a line, typing `# `, `## `, `### `, `- `, `* `, `1. `, `[] ` or `> ` SHALL give that line a Title, Heading, Subheading, dashed list, bulleted list, numbered list, checklist or quote, with the marks taken away, and one Undo SHALL give back the marks. The page SHALL show each style as it looks, never its marks.

#### Scenario: Tick an item while reading
- **WHEN** the keyboard is down and the person taps the circle of a checklist line
- **THEN** the line shows ticked, the keyboard stays down, and the change is kept

#### Scenario: A heading
- **WHEN** the person puts the cursor on a line and picks *Heading*
- **THEN** that whole line shows larger and bold, and the other lines keep their style

#### Scenario: Highlight in pink
- **WHEN** the person selects words, picks pink from the colour dot, and taps the pen
- **THEN** the words show with a pink highlight, and a second tap on the pen takes the highlight away

#### Scenario: Type a checklist
- **WHEN** the person types `[] ` at the start of an empty line
- **THEN** the line becomes an open checklist item with no `[]` in it

### Requirement: Styles stay readable as plain text

A note's styles SHALL be kept inside its words as Markdown, so the server, the AI connector, the API and webhooks get readable text with no new field. Underline, which Markdown lacks, SHALL be kept as `<u>…</u>`, and a highlight as `<mark class="<colour>">…</mark>`. A link on words SHALL be kept as `[words](address)`, and a table as a Markdown table. A note written before this change, with no marks, SHALL open with the same words and its first line as a title. Text that holds Markdown-like marks SHALL keep them when the person changes nothing.

#### Scenario: A checklist sent to a webhook
- **WHEN** a note with a ticked line *Milk* and an open line *Eggs* is sent
- **THEN** its words in the `note.created` message read `- [x] Milk` and `- [ ] Eggs`

#### Scenario: Opening an old note
- **WHEN** the person opens a note saved before editing existed and leaves without changing it
- **THEN** its words stay exactly as they were, and it is not sent again

#### Scenario: A highlight and a link sent to a webhook
- **WHEN** a note with *hall* highlighted in pink and *menu* linked to `https://example.com/menu` is sent
- **THEN** its words read `<mark class="pink">hall</mark>` and `[menu](https://example.com/menu)`, and the note opens again with the same highlight and link

### Requirement: A change to a sent note is sent

While sending is on, a change to a note already sent SHALL be sent once the person stops editing it, with the note's latest words and any files added. With Relay Everything picked, the server SHALL keep the new words in place of the old, and the page, the AI connector and the API SHALL read the new words. With the person's own webhook picked, the phone SHALL send a `note.updated` message there. A change made while offline or while a note waits to send SHALL go with the next send, and only the latest words SHALL arrive. A phone key SHALL be able to change any note in its own person's space, and SHALL add files only to a note it sent. When two changes of one note meet, the server SHALL keep the one made later and refuse the older one, whatever order they arrive in. A key SHALL NOT change a note in another person's space. With sending off, a change SHALL stay on the phone.

#### Scenario: Change a sent note
- **WHEN** sending to Relay Everything is on and the person changes a sent note's words
- **THEN** the note on the page shows the new words, and each of the person's webhooks gets one `note.updated` message

#### Scenario: Another device's note
- **WHEN** a phone key changes a note that another device or way in sent to the same person's space
- **THEN** the server keeps the new words, and each of the person's webhooks gets one `note.updated` message

#### Scenario: An older change
- **WHEN** a phone key sends a change made before the note's last change
- **THEN** the server refuses it, keeps the newer words, and sends no `note.updated` message

#### Scenario: Another person's note
- **WHEN** a phone key asks to change a note in another person's space
- **THEN** the server finds no such note, and the note stays as it was

### Requirement: Icons in Apple's style

Every icon in the phone app SHALL be drawn in Apple's thin, round style, in the theme's colors, on both iPhone and Android.

#### Scenario: Android
- **WHEN** the person opens the notes list on an Android phone
- **THEN** the search, ⋯, compose and back icons look the same as on an iPhone

### Requirement: Links in a note open in the browser

A web address in a note's words SHALL show as a link in the accent color, also when it was typed or pasted as plain text. The person SHALL be able to select words and give them a link with *Link*, which asks for the address and fills it in from a copied address; *Link* on a link SHALL change its address or take the link away. While the person reads the note, a tap on a link SHALL open it in the phone's browser; while they edit, a tap SHALL put the cursor in it. Showing a typed or pasted address as a link SHALL NOT change the note's stored words or send it again.

#### Scenario: Open a pasted address

- **WHEN** a note holds `https://id.onfido.com/XX6L46TU` as plain text and the person taps it with the keyboard down
- **THEN** the phone's browser opens that address, and the note is not marked to send again

#### Scenario: Edit a link's words

- **WHEN** the person is editing and taps the address
- **THEN** the cursor goes into the address and no browser opens

#### Scenario: Link selected words

- **WHEN** the person has copied `https://example.com/menu`, selects *the menu*, and taps *Link*
- **THEN** the address box shows `https://example.com/menu`, and after *Done* the words *the menu* show as a link to it

### Requirement: A note's page says nothing about sending

A note's page SHALL show only its date at the top. It SHALL show no *Sent*, no *Waiting to send*, no *Send now* and no *Voice* or *Typed* tag, and its ⋯ menu SHALL have no item to send or sync.

#### Scenario: A waiting note

- **WHEN** the person opens a note that waits to send
- **THEN** the top of the page shows only the date, and ⋯ has no *Send now*

#### Scenario: A sent note

- **WHEN** the person opens a note that is sent
- **THEN** the top of the page shows only the date, and the page has no *Sent* line and no tag

### Requirement: The text menu is the iPhone's own

While the person edits a note on an iPhone that can show the system text menu (iOS 16 and later), a hold, a selection, or a tap on the cursor SHALL show the iPhone's own text menu, with the standard items that fit the selection: *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Search Web* and *Share*. A tap on *Paste* SHALL put in the words from the clipboard at the cursor, with the formatting the note can show (see *A paste keeps its formatting*), with no *Allow Paste?* question, also for words copied in another app. A tap on the blinking cursor SHALL open the menu, and a second tap SHALL close it; a tap anywhere else SHALL move the cursor there, as before. While the person drags the cursor or a selection handle, a magnifier SHALL show the words under the finger. Where the iPhone's own menu can't show (an older iPhone or Android), the app SHALL show its own menu with the same actions, and the browser SHALL keep the browser's own menu.

#### Scenario: Paste words from another app

- **WHEN** the person copies `Buy oat milk` in Safari, opens a note, and taps *Paste* in the menu after a hold in the words
- **THEN** `Buy oat milk` is in the note at the cursor, in the note's style, and no *Allow Paste?* question showed

#### Scenario: Tap the cursor to open the menu

- **WHEN** the person types in a note and taps on the blinking cursor
- **THEN** the iPhone's own menu shows *Paste* above the cursor, and a second tap on the cursor closes it

### Requirement: Undo and Redo while typing

While the keyboard is up and the note has a change since the page opened, the top SHALL show an *Undo* button left of share and ⋯. A tap SHALL take back the last change and keep the keyboard up. After an undo, a *Redo* button SHALL show beside *Undo* and SHALL put the change back; a new change SHALL remove *Redo*. Undo SHALL go back no further than the words the page opened with. An undone change SHALL be kept and sent as any change is.

#### Scenario: Undo a line
- **WHEN** the person opens a note, types *buy milk*, and taps *Undo*
- **THEN** *buy milk* goes, the keyboard stays up, and *Redo* shows beside *Undo*

#### Scenario: Nothing to undo
- **WHEN** the person opens a note and taps into it without a change
- **THEN** the top shows no *Undo* and no *Redo*

### Requirement: Find in Note

On a phone, *Find in Note* in a note's ⋯ menu SHALL show a find bar over the keyboard in place of the tool bar: a field for the words to find, the place of the current match out of all matches, such as *2 of 14*, and up and down buttons. Matching SHALL ignore capital letters. The page SHALL select the current match and scroll it into view; down SHALL go to the next match and up to the one before, each going round at the end. Finding SHALL NOT change the note. ✓, a tap in the note's words, or leaving the page SHALL close the find bar; after a tap in the words, the person edits the note with the tool bar back.

#### Scenario: Step through matches
- **WHEN** a note holds *Train* once and *train* twice, and the person finds *train* and taps down twice
- **THEN** the bar reads *1 of 3*, then *2 of 3*, then *3 of 3*, with each match selected in turn, and the note's words are unchanged

#### Scenario: No match
- **WHEN** the person finds words the note does not hold
- **THEN** the bar reads *No matches* and up and down do nothing

### Requirement: A paste keeps its formatting

A paste into a note SHALL keep each style the note can show: headings (a level past 3 becomes level 3), bullet, dashed, numbered and checklist items with their indent, quotes, code blocks, links on words, tables, and bold, italic, underlined and struck-through words. It SHALL drop colors, fonts, sizes, backgrounds, alignment, pictures and other styles the note can't show, so the pasted words take the note's own look. Pasted plain text SHALL be read as Markdown, as a note's own words are read, so `## Plan` pastes as a heading and `**now**` as bold. A link whose words differ from its address SHALL paste as its words, linked to its address. Runs of empty lines SHALL become one, and empty lines at the start and end SHALL go. A paste of one line with no line style SHALL join the line at the cursor. The pasted note SHALL be stored as the Markdown the page shows, so it opens the same again. This SHALL hold for the iPhone's own *Paste*, the app's own menu, a keyboard's paste keys, and the Relay Everything web page. A copy from inside a note SHALL paste back with its styles. One *Undo* SHALL take back the whole paste.

#### Scenario: Paste a list from a web page

- **WHEN** the person copies a heading, a sentence with a bold word, and a bullet list from a web page, and pastes them into a note
- **THEN** the note shows the heading, the bold word, and the bullet items, in the note's own font and colors

#### Scenario: Paste Markdown from a chat

- **WHEN** the person copies `## Plan`, `- [ ] Call the bank` and `- Buy **oat** milk` as plain text and pastes them
- **THEN** the note shows the heading *Plan*, an open checklist item *Call the bank*, and a dashed item *Buy oat milk* with *oat* in bold

#### Scenario: Paste a link with its own words

- **WHEN** the person pastes a link whose words are `the menu` and whose address is `https://example.com/menu`
- **THEN** the note shows `the menu` as a link to `https://example.com/menu`, and keeps it as `[the menu](https://example.com/menu)`

#### Scenario: Paste a few words into a line

- **WHEN** the person pastes `oat` in the middle of the line `Buy milk`
- **THEN** the line reads `Buy oat milk` and keeps its own style

#### Scenario: Undo a paste

- **WHEN** the person pastes a formatted list and taps *Undo*
- **THEN** the whole pasted list goes in one step
