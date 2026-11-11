## MODIFIED Requirements

### Requirement: The app works offline by default

A newly installed Relay phone app SHALL let the person write and read notes with no key, no server and no connection, and SHALL make no network request while sending is off, except to get the speech model after the person agrees to it.

#### Scenario: First open with no key
- **WHEN** the person opens the app for the first time and writes a note
- **THEN** the note is saved and shown in the timeline, and the app asks for no key

#### Scenario: A week of notes with sending off
- **WHEN** the person writes notes and opens Settings with sending off
- **THEN** the app sends nothing to any server, reads no place and looks up no place names

#### Scenario: Voice notes with sending off
- **WHEN** sending is off and the person agrees to get the speech model, then makes voice notes
- **THEN** the only request is the model's download, and no voice note, recording or word leaves the phone
