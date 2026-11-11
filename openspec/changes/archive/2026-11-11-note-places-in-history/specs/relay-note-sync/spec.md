## MODIFIED Requirements

### Requirement: A signed-in phone gets every note in its space

While sending is on and Relay Everything is picked, the phone app SHALL get every note in its person's space, from any device or way in, and each change to one, and SHALL show each note with where it came from. A phone that syncs for the first time SHALL get all the notes already there. A note the phone sent itself SHALL show once, never twice. New notes and changes SHALL come in when the app opens or comes back, when the person pulls down the list, and in the background round.

#### Scenario: A note from the other phone
- **WHEN** a person writes a note on their iPhone, and later opens the app on their Pixel, signed in with sending on
- **THEN** the Pixel lists the note, marked as from the iPhone

#### Scenario: A new phone
- **WHEN** a person signs in on a new phone that has 300 notes in its space
- **THEN** the phone lists all 300 notes, with the words and file list of each
