# relay-note-editing Specification

## Purpose
Lets a person write and change a note in place on the phone, with Apple Notes text styles, lists and checklists, and keeps a sent note's copies on the server and webhooks current.

## Requirements

### Requirement: A note edits in place

A tap on a note's words SHALL put the cursor there and bring up the keyboard, on the same page that shows the note. A new note SHALL open on that page with the keyboard up and its first line styled as a title. Each change SHALL be kept on the phone within two seconds of a pause in typing, and when the person leaves the page, with no *Save* button. A note left with no words and no files SHALL be deleted from the phone when the person leaves it, as Apple Notes does, with any upload or change of it still waiting, so it is never sent; a copy already on the server SHALL keep its last words. A voice note left with no words SHALL keep its recording. A voice note's words SHALL be editable, and its recording SHALL stay unchanged.

#### Scenario: Fix a word and leave
- **WHEN** the person opens a note, taps a word, types a fix and taps back
- **THEN** the list shows the note with the fix, and the fix is still there after the app restarts

#### Scenario: An empty new note
- **WHEN** the person opens a new note and leaves without typing or adding a file
- **THEN** no note is added to the list

#### Scenario: An emptied note
- **WHEN** the person deletes every word of a note that has no files or recording, and leaves
- **THEN** the note is gone from the list and nothing of it is sent; a copy already sent keeps its last words on the page

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float above it with *Text styles*, *Checklist* and *Attach*, and the top SHALL show back, share, ⋯ and a done button that closes the keyboard. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach* and a compose button that opens a new note. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with the compose button shows

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

While sending is on, a change to a note already sent SHALL be sent once the person stops editing it, with the note's latest words and any files added. With Relay Everything picked, the server SHALL keep the new words in place of the old, and the page, the AI connector and the API SHALL read the new words. With the person's own webhook picked, the phone SHALL send a `note.updated` message there. A change made while offline or while a note waits to send SHALL go with the next send, and only the latest words SHALL arrive. Only the device key that sent a note SHALL be able to change it. With sending off, a change SHALL stay on the phone.

#### Scenario: Change a sent note
- **WHEN** sending to Relay Everything is on and the person changes a sent note's words
- **THEN** the note on the page shows the new words, and each of the person's webhooks gets one `note.updated` message

#### Scenario: Another device's note
- **WHEN** a device key asks to change a note another device sent
- **THEN** the server refuses, and the note stays as it was

### Requirement: Icons in Apple's style

Every icon in the phone app SHALL be drawn in Apple's thin, round style, in the theme's colors, on both iPhone and Android.

#### Scenario: Android
- **WHEN** the person opens the notes list on an Android phone
- **THEN** the search, ⋯, compose and back icons look the same as on an iPhone
