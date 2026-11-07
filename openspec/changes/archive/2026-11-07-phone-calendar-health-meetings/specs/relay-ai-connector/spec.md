## MODIFIED Requirements

### Requirement: The AI reads but never changes

Every connector tool but one SHALL be marked read-only and SHALL only read notes, health samples, locations, calendar events and saved chats. The one other tool SHALL add a typed note, and only for an app connected with the words that say it can add notes. No tool SHALL edit or delete any Relay Everything data, and recordings SHALL NOT be returned.

#### Scenario: The AI is asked to delete a note
- **WHEN** a chat asks the AI to delete or edit a Relay note
- **THEN** no connector tool can do it and the note stays as it is

#### Scenario: The AI saves a note
- **WHEN** a person asks a connected AI app to save something as a note
- **THEN** the note shows on their page with the app's name as its device

#### Scenario: An app connected before notes could be added
- **WHEN** an app connected before this change tries to add a note
- **THEN** it is refused with a message to connect again, and its reads still work

#### Scenario: The AI reads the day's calendar
- **WHEN** a chat asks what is on the person's day
- **THEN** the AI reads that day's events, with times and people, and no event is changed
