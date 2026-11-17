## MODIFIED Requirements

### Requirement: A note can hold files

A note made in the app or by Shortcuts SHALL hold up to 10 files of any kind, each up to 25 MB, with or without words. A recording made in the app, by Shortcuts or on the watch SHALL be one of these files, and SHALL carry its transcript, its length, and whether it is the recording the note started with. The app SHALL refuse a file over the limit, or an eleventh file, with a message, and keep the rest. The timeline SHALL show a picture as a picture, a recording as its card, and any other file by its name and size, each at its place in the note's words, and SHALL open a file when tapped. A file with no place in the words SHALL show after the words in the order it was added, except the recording a voice note starts with, which SHALL show before the words.

#### Scenario: A receipt and a PDF
- **WHEN** the person writes *Receipt for the desk lamp*, adds a photo and a PDF with the paperclip, and saves
- **THEN** the timeline shows the words, the photo, and a *warranty.pdf* row with its size

#### Scenario: An eleventh file
- **WHEN** a note holds 9 files and a recording, and the person taps the mic
- **THEN** the app says the note holds 10 files already and records nothing

#### Scenario: A file too big
- **WHEN** the person adds a 40 MB video
- **THEN** the app says the file is over 25 MB and adds nothing for it

## ADDED Requirements

### Requirement: Files sit at a place in the note's words

The note page SHALL show each picture, file and recording as its own block in the note's words, and the person SHALL be able to type above it, below it, and between two of them. A file added with *Attach* or the mic SHALL go at the cursor's line, or at the end of the note when the note has no cursor. The note's text SHALL mark each file's place with one line, `![<name>](attachment:<id>)`, so the phones, the web page, the Mac app, AI apps and webhooks read the same order. A note's list row, search and *Share* SHALL leave these lines out.

#### Scenario: Words after a photo
- **WHEN** the person writes *Prices for the ring board*, adds a photo, and types *Lead time is two weeks* under it
- **THEN** the note shows the words, the photo, then *Lead time is two weeks*, in that order, also after the app restarts and on the web page

#### Scenario: An older note
- **WHEN** the person opens a voice note made before this change and types under its recording
- **THEN** the recording stays at the top with the new words under it, and the order is kept after the note closes

### Requirement: The person can remove a file from a note

On a note made on this device, the person SHALL remove a picture, file or recording with delete, as they remove words. Undo SHALL bring it back while the note is open. A removed file SHALL go from the note on each device and from the person's space, and each active webhook SHALL get `note.updated` without it. A file on a note from another device SHALL NOT be removable.

#### Scenario: Remove a photo
- **WHEN** sending is on, the person puts the cursor after a photo in their note and presses delete
- **THEN** the photo goes from the note, the person's space no longer holds it, and the web page shows the note without it

#### Scenario: Undo a removal
- **WHEN** the person removes a recording and taps Undo before closing the note
- **THEN** the recording is back at its place with its transcript, and it is in the person's space again
