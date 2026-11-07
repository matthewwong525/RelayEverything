## MODIFIED Requirements

### Requirement: Other services read and add through one web API

Relay Everything SHALL offer a web API that answers the same questions as the AI connector: search notes, read one note, read notes in a time range, sum up a day, read health over time, read places, read calendar events, search saved chats and read one chat. It SHALL also add a typed note. It SHALL NOT change or delete any data, and SHALL NOT return a recording, a key, or a device's id. Each answer SHALL have the same size limits as the AI connector, with a way to read the next page.

#### Scenario: A script reads yesterday's notes
- **WHEN** a script with a person's API key asks for the notes from yesterday
- **THEN** it gets that person's notes from yesterday, at most one page, with a way to read the next

#### Scenario: A caller tries to delete
- **WHEN** a caller with a valid token or API key sends a request to delete or change a note
- **THEN** it is refused and the note stays as it is
