## MODIFIED Requirements

### Requirement: A mic in a note adds a recording

The note page on a phone SHALL have a mic button that records into the open note, on the same full-screen recording screen as a held *New note*: a tap saves and the X keeps nothing. Each saved recording SHALL show as its own card at the cursor's line, or at the end of the note when the note has no cursor, as an added photo does, and its transcript SHALL be written on the phone as for a held voice note. A recording with no words found SHALL stay in the note and show that no words were heard. The mic SHALL NOT show for a note that came from another device, as *Attach* does not, and SHALL refuse a recording once the note holds 10 files, with a message.

#### Scenario: A second recording
- **WHEN** the person opens a voice note with one recording and typed notes, taps the end of the typed notes, taps the mic, says a sentence and taps the screen
- **THEN** the first recording stays at the top, the new card shows under the typed notes, and its transcript fills in

#### Scenario: A recording between two lines
- **WHEN** the person puts the cursor at the end of the first of two lines, taps the mic, says a sentence and taps the screen
- **THEN** the new card shows between the two lines

#### Scenario: Cancel
- **WHEN** the person taps the mic in a note and then the X
- **THEN** the note is as it was, with no new recording
