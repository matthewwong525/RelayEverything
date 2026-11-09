## ADDED Requirements

### Requirement: Notes come before the phone's other data

When the app opens, comes back to the front, when the person pulls down a list, or taps **Sync now**, the phone app SHALL send this phone's waiting notes, note changes, note deletes and note files, and then get the notes changed elsewhere, before it reads or sends health, location points, stays and trips, calendar events or photos. A failed or slow health, place, calendar or photo upload SHALL NOT stop or delay the notes. The sync state on Home SHALL report only the notes: *Syncing* SHALL end when the notes are sent and got, also while the other data still sends. A note kept, or a pull asked for, while the other data sends SHALL stop that work at its next upload, and the phone SHALL then send the notes and get new notes before it goes on. The background round SHALL also send the notes and get new notes before the other data.

#### Scenario: New notes come in before health data sends

- **WHEN** the app opens with 2,000 health readings and one note waiting, and another phone changed a note
- **THEN** the phone sends its note and shows the other phone's change before it sends the health readings

#### Scenario: A failed photo upload does not stop notes

- **WHEN** a photo upload fails during the round, and another phone added a note
- **THEN** the phone still gets and shows the other phone's note, and the photo waits for a later round

#### Scenario: Syncing ends with the notes

- **WHEN** the notes are sent and got, and the phone still sends location points
- **THEN** Home shows *Synced*, not *Syncing*, and pull to refresh ends

#### Scenario: A new note goes before the rest of the round

- **WHEN** the person keeps a note while the phone sends health readings
- **THEN** the phone stops the health readings at their next upload, sends the note, then sends the health readings that wait

#### Scenario: The background round sends notes first

- **WHEN** a background wake runs with a note and health readings waiting for Relay Everything
- **THEN** the note goes before the health readings
