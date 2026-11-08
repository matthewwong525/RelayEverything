# relay-voice-notes Specification

## Purpose
Let a person talk a note into the Relay phone app and get its words written on the phone itself, with their voice never leaving the phone.

## Requirements

### Requirement: A held voice note becomes a note with words

The phone app SHALL start recording when the person holds *New note* for half a second, SHALL keep recording after the finger lifts, and SHALL stop and save when the person taps anywhere on the screen. It SHALL write the recording's words on the phone with no speech service on any network, and SHALL show the note in the timeline at once, with its words when they are ready. It SHALL work with no signal and with sending off. When the words fail, or are not written within 2 minutes or the recording's length if longer, the note SHALL keep its recording, SHALL say that the words did not come, and SHALL offer **Try again**; it SHALL NOT show *Writing the words…* after that.

#### Scenario: A voice note in airplane mode
- **WHEN** the speech model is on the phone, the phone has no connection, and the person holds *New note* until it turns into a mic, lets go, says a sentence and taps the screen
- **THEN** the note shows at once, its words fill in, and no request leaves the phone

#### Scenario: The app closes before the words are written
- **WHEN** the app is closed while a voice note's words are being written
- **THEN** the next time the app opens, it writes them from the kept recording

#### Scenario: The words fail
- **WHEN** writing a voice note's words fails with any error
- **THEN** the note keeps its recording, shows *The words did not come. Your recording is safe.* and **Try again**, and the app shows a notice once

#### Scenario: The words take too long
- **WHEN** a voice note's words are not written within the time limit
- **THEN** the app stops the writing and the note shows the same failed state

#### Scenario: Try again
- **WHEN** the person taps **Try again** on a failed note, or opens the app again
- **THEN** the app writes the words again from the kept recording

### Requirement: No speech, no note

The phone app SHALL keep no note, and no recording, from a press of *New note* shorter than half a second, from a recording the person cancels, or from a recording in which no words are found. A press shorter than half a second SHALL open the page to write a note instead.

#### Scenario: A bump in a pocket
- **WHEN** *New note* is pressed for 0.3 s
- **THEN** nothing records, no voice note is saved, and the page to write a note opens

#### Scenario: A silent recording
- **WHEN** the person records for 4 s, says nothing, and taps the screen
- **THEN** the app says it heard no speech, and keeps no note and no recording

### Requirement: The speech model is fetched only with the person's yes

The phone app SHALL get the speech model only after the person agrees to it, the first time they use voice notes; SHALL refuse a model file that does not match its known checksum; and SHALL let the person remove it.

#### Scenario: First voice note
- **WHEN** the person holds *New note* for half a second with no speech model on the phone
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
