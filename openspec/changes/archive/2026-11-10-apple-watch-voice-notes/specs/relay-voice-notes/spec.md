## ADDED Requirements

### Requirement: A watch recording becomes a voice note

The phone app SHALL keep each recording its paired Apple Watch hands it as a voice note, at the time the person saved it on the watch, with no place, and SHALL write its words on the phone by the same rules as a held voice note: no speech service on any network, the same failed state and **Try again**, and no note when no words are found. It SHALL keep the note at once when the app runs, and else the next time it opens. The recording SHALL stay on the phone, and only the note's words SHALL be sent, only while sending is on.

#### Scenario: A watch note while the app runs
- **WHEN** the phone app is open, the speech model is on the phone, and the watch hands it a recording of a sentence
- **THEN** a voice note shows in *Voice notes* at once, and its words fill in

#### Scenario: A watch note while the app is closed
- **WHEN** the watch hands a recording while the phone app is closed
- **THEN** the next time the app opens, the note shows once, with the watch's save time, and its words are written
