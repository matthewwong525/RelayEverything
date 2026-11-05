# relay-voice-notes Specification

## Purpose
Let a person talk a note into the Relay phone app and get its words written on the phone itself, with their voice never leaving the phone.

## Requirements

### Requirement: A held voice note becomes a note with words

The phone app SHALL record while the person holds the voice button, SHALL write the recording's words on the phone with no speech service on any network, and SHALL show the note in the timeline at once, with its words when they are ready. It SHALL work with no signal and with sending off.

#### Scenario: A voice note in airplane mode
- **WHEN** the speech model is on the phone, the phone has no connection, and the person holds the button, says a sentence and lets go
- **THEN** the note shows at once, its words fill in, and no request leaves the phone

#### Scenario: The app closes before the words are written
- **WHEN** the app is closed while a voice note's words are being written
- **THEN** the next time the app opens, it writes them from the kept recording

### Requirement: No speech, no note

The phone app SHALL keep no note, and no recording, from a press shorter than half a second, from a press the person cancels, or from a recording in which no words are found.

#### Scenario: A bump in a pocket
- **WHEN** the button is held for 0.3 s
- **THEN** nothing is saved and the timeline does not change

#### Scenario: A silent recording
- **WHEN** the person holds the button for 4 s and says nothing
- **THEN** the app says it heard no speech, and keeps no note and no recording

### Requirement: The speech model is fetched only with the person's yes

The phone app SHALL get the speech model only after the person agrees to it, the first time they use voice notes; SHALL refuse a model file that does not match its known checksum; and SHALL let the person remove it.

#### Scenario: First voice note
- **WHEN** the person taps the voice button with no speech model on the phone
- **THEN** the app asks before it gets the model and its size, and gets nothing on *Not now*

#### Scenario: A damaged download
- **WHEN** the downloaded model does not match its known checksum
- **THEN** the app deletes it, keeps voice notes off, and offers to try again

### Requirement: The recording stays on the phone

The phone app SHALL keep a voice note's recording only on the phone, where the person can play it, and SHALL send only the note's words to the Relay server, and only while sending is on.

#### Scenario: A voice note with sending on
- **WHEN** sending is on and a voice note's words are written
- **THEN** the server gets the words and the time, and never the recording

#### Scenario: Words not written yet
- **WHEN** sending is on and a voice note's words are still being written
- **THEN** the note waits on the phone and is sent only when it has words
