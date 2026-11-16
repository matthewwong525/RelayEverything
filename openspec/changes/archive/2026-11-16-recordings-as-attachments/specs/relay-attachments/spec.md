## MODIFIED Requirements

### Requirement: A note can hold files

A note made in the app or by Shortcuts SHALL hold up to 10 files of any kind, each up to 25 MB, with or without words. A recording made in the app, by Shortcuts or on the watch SHALL be one of these files, and SHALL carry its transcript, its length, and whether it is the recording the note started with. The app SHALL refuse a file over the limit, or an eleventh file, with a message, and keep the rest. The timeline SHALL show a picture as a picture, a recording as its card, and any other file by its name and size, after the note's words in the order they were added, except the recording a voice note starts with, which shows before the words, and SHALL open a file when tapped.

#### Scenario: A receipt and a PDF
- **WHEN** the person writes *Receipt for the desk lamp*, adds a photo and a PDF with the paperclip, and saves
- **THEN** the timeline shows the words, the photo, and a *warranty.pdf* row with its size

#### Scenario: An eleventh file
- **WHEN** a note holds 9 files and a recording, and the person taps the mic
- **THEN** the app says the note holds 10 files already and records nothing

#### Scenario: A file too big
- **WHEN** the person adds a 40 MB video
- **THEN** the app says the file is over 25 MB and adds nothing for it

### Requirement: Webhooks name a note's files

A `note.created` or `note.updated` message for a note with files SHALL carry an `attachments` list with each file's id, name, content type and size, and SHALL NOT carry the file's bytes. A recording in the list SHALL also carry its transcript, empty until it is written, and its length. A note without files SHALL send the message it sends today. The public schema SHALL describe the list.

#### Scenario: A note with a PDF
- **WHEN** a note with *warranty.pdf* is stored and one webhook is active
- **THEN** the webhook's `note.created` message lists *warranty.pdf*, `application/pdf` and its size in bytes, and holds no file data

#### Scenario: A voice note
- **WHEN** a voice note with the spoken words *Call the fab* and no typed words is stored and one webhook is active
- **THEN** the webhook's `note.created` message has an empty `text`, and its `attachments` list holds the recording with the transcript *Call the fab* and its length

## ADDED Requirements

### Requirement: A recording's transcript reads with its note

The person's space SHALL keep each recording's transcript with the recording, SHALL give it with the note's files to the person's phones, the web page, the Mac app, the web API and the AI connector, and SHALL find a note by the words of its transcripts in a search. A change of a transcript from the phone that made the note SHALL be kept by the same newest-change rule as a change of the note's words, and SHALL go to the webhooks as `note.updated`. The AI connector and the web API SHALL give the transcript and SHALL NOT give the recording's sound.

#### Scenario: An AI app searches
- **WHEN** an AI app searches the person's notes for *brass* and only a recording's transcript holds it
- **THEN** the note is found, with the transcript in its file list, and no sound

#### Scenario: A corrected word
- **WHEN** the person changes *fab* to *lab* in a sent recording's transcript
- **THEN** the space keeps *lab*, and each active webhook gets a `note.updated` message with the new transcript
