## REMOVED Requirements

### Requirement: A note's file can go as its own message
**Reason**: The server's webhooks now send each stored file too, so a server receiver no longer gets only a list of file names; Milestone 1 needs every file in the owner's database.
**Migration**: A receiver saves `note.file` as the phone's own-webhook mode already sends it. One built before answers 2xx to a type it does not know, as the docs say.

## ADDED Requirements

### Requirement: A note's files go as their own messages

Format v1 SHALL include a `note.file` message that holds one file of a note: the note's id, the file's id, name, type and size, and its contents in base64. The server SHALL send it to every active webhook for each file whose bytes it stores, and the phone's own webhook mode SHALL send it for each file it holds, always after the note's `note.created`. The `note.created` message SHALL keep listing the note's files. When an address answers 413 to a `note.file`, that file SHALL be skipped, the webhook SHALL name it with its last answer, and the file SHALL stay in Relay Everything; any other failure SHALL be retried like every message. Files stored before the server sent `note.file` SHALL be sent once. The published schema and the example receiver SHALL include `note.file`, and the example receiver SHALL keep each listed file, with its bytes once they come.

#### Scenario: A note with a photo
- **WHEN** a phone's note with one photo is stored, then the photo's bytes, and one active webhook exists
- **THEN** that address gets the `note.created` that lists the photo, then a `note.file` with the photo's bytes and the same file id

#### Scenario: A receiver that takes only small bodies
- **WHEN** an address answers 413 to a 20 MB file and 200 to everything else
- **THEN** the webhook skips that file, names it on its card, and sends the next note

#### Scenario: The example receiver saves a file
- **WHEN** the example receiver gets a `note.created` that lists a file and then a `note.file` for that note
- **THEN** it keeps the file's name from the first message and saves its bytes beside the note from the second
