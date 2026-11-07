## MODIFIED Requirements

### Requirement: The AI reads but never changes

Every connector tool SHALL be marked read-only and SHALL only read notes, health samples, locations, chats and photos; no tool SHALL add, edit or delete any Relay data, and recordings SHALL NOT be returned. A photo SHALL be returned only one at a time, as an image, by its id.

#### Scenario: The AI is asked to delete a note
- **WHEN** a chat asks the AI to delete or edit a Relay note
- **THEN** no connector tool can do it and the note stays as it is

#### Scenario: The AI looks at photos from a trip
- **WHEN** a chat asks for the photos taken near a place over a few days
- **THEN** the AI gets a capped, pageable list with each photo's time and place, and can open each photo as an image
