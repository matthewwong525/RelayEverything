## MODIFIED Requirements

### Requirement: A synced note's files open on tap

A synced phone SHALL list each note's files by name, type and size, with each recording's transcript and length, and SHALL download a file only when the person opens it, or a recording only when the person plays it. A recording the server never got, such as one made while sending was off, SHALL stay only on the phone that made it.

#### Scenario: A boarding pass from email
- **WHEN** a person opens a synced email note on their phone and taps its PDF
- **THEN** the phone downloads the PDF and opens it, and no other file of that note is downloaded

#### Scenario: A recording from the other phone
- **WHEN** a person opens on their Pixel a note recorded on their iPhone, and taps play
- **THEN** the Pixel shows the transcript at once, downloads the recording, and plays it
