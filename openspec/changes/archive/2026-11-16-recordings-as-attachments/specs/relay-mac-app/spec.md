## MODIFIED Requirements

### Requirement: The Mac sends no private phone data

The Mac app SHALL NOT read or send health, location, calendar or photo data, and SHALL NOT ask the Mac for those permissions. It SHALL NOT record voice notes. A recording made on a phone SHALL show as its card with its transcript, and SHALL play from the person's space once the sound is there.

#### Scenario: A voice note from the phone

- **WHEN** the person opens a voice note recorded on their phone and sent with its recording
- **THEN** the Mac shows the recording's card with its transcript, play plays the recording, and the Mac shows no button to record
