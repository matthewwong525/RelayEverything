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

While the keyboard is up, a tool bar SHALL float above it with *Text styles*, *Checklist* and *Attach*, and the top SHALL show back, share, ⋯ and a done button that closes the keyboard. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach* and a compose button that opens a new note. The ⋯ menu SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with the compose button shows

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

### Requirement: Text styles, lists and checklists

*Text styles* SHALL offer Title, Heading, Subheading, Body and Monostyled for a line; bold, italic, underline and strikethrough for selected words; bulleted, dashed and numbered lists; block quote; and indent in and out. A checklist line SHALL show a circle that one tap ticks or unticks, also while the keyboard is down. Return on an empty list or checklist line SHALL end the list. The page SHALL show each style as it looks, never its marks.

#### Scenario: Tick an item while reading
- **WHEN** the keyboard is down and the person taps the circle of a checklist line
- **THEN** the line shows ticked, the keyboard stays down, and the change is kept

#### Scenario: A heading
- **WHEN** the person puts the cursor on a line and picks *Heading*
- **THEN** that whole line shows larger and bold, and the other lines keep their style

### Requirement: Styles stay readable as plain text

A note's styles SHALL be kept inside its words as Markdown, so the server, the AI connector, the API and webhooks get readable text with no new field. Underline, which Markdown lacks, SHALL be kept as `<u>…</u>`. A note written before this change, with no marks, SHALL open with the same words and its first line as a title. Text that holds Markdown-like marks SHALL keep them when the person changes nothing.

#### Scenario: A checklist sent to a webhook
- **WHEN** a note with a ticked line *Milk* and an open line *Eggs* is sent
- **THEN** its words in the `note.created` message read `- [x] Milk` and `- [ ] Eggs`

#### Scenario: Opening an old note
- **WHEN** the person opens a note saved before editing existed and leaves without changing it
- **THEN** its words stay exactly as they were, and it is not sent again

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

A web address in a note's words SHALL show as a link in the accent color, also when it was typed or pasted as plain text. While the person reads the note, a tap on the link SHALL open it in the phone's browser; while they edit, a tap SHALL put the cursor in it. Showing a link SHALL NOT change the note's stored words or send it again.

#### Scenario: Open a pasted address

- **WHEN** a note holds `https://id.onfido.com/XX6L46TU` as plain text and the person taps it with the keyboard down
- **THEN** the phone's browser opens that address, and the note is not marked to send again

#### Scenario: Edit a link's words

- **WHEN** the person is editing and taps the address
- **THEN** the cursor goes into the address and no browser opens

### Requirement: Tap Waiting to send to send now

While a note waits to send, its *Waiting to send* line on the note's page SHALL be a button that sends what waits now, and SHALL say *Sending…* while it goes.

#### Scenario: Send a waiting note

- **WHEN** a note says *Waiting to send*, the phone has a connection, and the person taps it
- **THEN** the phone sends what waits, the line says *Sending…*, then *Sent*

### Requirement: The text menu is the iPhone's own

While the person edits a note on an iPhone that can show the system text menu (iOS 16 and later), a hold, a selection, or a tap on the cursor SHALL show the iPhone's own text menu, with the standard items that fit the selection: *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Search Web* and *Share*. A tap on *Paste* SHALL put in the words from the clipboard at the cursor as plain text, in the note's own style, with no *Allow Paste?* question, also for words copied in another app. A tap on the blinking cursor SHALL open the menu, and a second tap SHALL close it; a tap anywhere else SHALL move the cursor there, as before. While the person drags the cursor or a selection handle, a magnifier SHALL show the words under the finger. Where the iPhone's own menu can't show (an older iPhone or Android), the app SHALL show its own menu with the same actions, and the browser SHALL keep the browser's own menu.

#### Scenario: Paste words from another app

- **WHEN** the person copies `Buy oat milk` in Safari, opens a note, and taps *Paste* in the menu after a hold in the words
- **THEN** `Buy oat milk` is in the note at the cursor as plain text, in the note's style, and no *Allow Paste?* question showed

#### Scenario: Tap the cursor to open the menu

- **WHEN** the person types in a note and taps on the blinking cursor
- **THEN** the iPhone's own menu shows *Paste* above the cursor, and a second tap on the cursor closes it
