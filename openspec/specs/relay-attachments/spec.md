# relay-attachments Specification

## Purpose
Let a note hold files, kept on the phone and sent sealed to the person's own space only while sending is on, shown on the page and named in webhook messages.

## Requirements

### Requirement: A note can hold files

A note made in the app or by Shortcuts SHALL hold up to 10 files of any kind, each up to 25 MB, with or without words. The app SHALL refuse a file over the limit, or an eleventh file, with a message, and keep the rest. The timeline SHALL show a picture as a picture and any other file by its name and size, and SHALL open a file when tapped.

#### Scenario: A receipt and a PDF
- **WHEN** the person writes *Receipt for the desk lamp*, adds a photo and a PDF with the paperclip, and saves
- **THEN** the timeline shows the words, the photo, and a *warranty.pdf* row with its size

#### Scenario: A file too big
- **WHEN** the person adds a 40 MB video
- **THEN** the app says the file is over 25 MB and adds nothing for it

### Requirement: Files go to the person's space only while sending

A note's files SHALL leave the phone only while sending is on, or when the person picks *Send them* for earlier notes, and SHALL go only to the person's own space. A resent file SHALL be stored once. In the space, each file SHALL be sealed with the space's own key, readable only by that person's sign-in, and deleted with the account.

#### Scenario: A note with files while sending is on
- **WHEN** sending is on and the person saves a note with two files
- **THEN** the person's page shows the note with both files, and another person's sign-in can't open them

#### Scenario: The phone loses its answer
- **WHEN** the phone sends a file again after a lost answer
- **THEN** the space keeps one copy of the file

### Requirement: The page shows a note's files

The person's Relay Everything page SHALL show a note's pictures in the note, and every other file as a link that downloads it with its name. A file that has not arrived yet SHALL show as waiting.

#### Scenario: A note whose file is still on its way
- **WHEN** the note reached the space and its file has not
- **THEN** the page shows the file's name as waiting, and the file once it arrives

### Requirement: Webhooks name a note's files

A `note.created` message for a note with files SHALL carry an `attachments` list with each file's id, name, content type and size, and SHALL NOT carry the file's bytes. A note without files SHALL send the message it sends today. The public schema SHALL describe the list.

#### Scenario: A note with a PDF
- **WHEN** a note with *warranty.pdf* is stored and one webhook is active
- **THEN** the webhook's `note.created` message lists *warranty.pdf*, `application/pdf` and its size in bytes, and holds no file data
