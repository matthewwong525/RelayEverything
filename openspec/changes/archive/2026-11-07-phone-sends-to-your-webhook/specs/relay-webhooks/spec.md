## ADDED Requirements

### Requirement: A note's file can go as its own message

Format v1 SHALL include a `note.file` message that holds one file of a note: the note's id, the file's id, name, type and size, and its contents in base64. Only the phone's own webhook mode SHALL send it, always after the note's `note.created`. The server's webhooks SHALL keep sending a list of file names only. The published schema and the example receiver SHALL include `note.file`.

#### Scenario: A server webhook receiver is unchanged
- **WHEN** a receiver built before `note.file` takes messages from a server webhook
- **THEN** it never gets a `note.file` message

#### Scenario: The example receiver saves a file
- **WHEN** the example receiver gets a `note.created` and then a `note.file` for that note
- **THEN** it saves the file beside the note
