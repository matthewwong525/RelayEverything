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

### Requirement: A saved voice note opens its page

When the person taps to save a voice note, from a hold on *New note* or from Shortcuts and the Action button, the phone app SHALL open the new note's page at once, over the page that was open, and its words SHALL fill in on that page. Back SHALL return to the page that was open before. *Cancel*, a recording too short to keep, a recording that stops itself at its longest length, and a note the phone could not keep SHALL open no page.

#### Scenario: Tap to save
- **WHEN** the person holds *New note*, talks, and taps the screen
- **THEN** the note's page opens, shows *Writing the words…*, and then shows the words; Back shows the notes list

#### Scenario: Cancel
- **WHEN** the person taps *Cancel* on the listening card
- **THEN** no note is kept and no page opens

### Requirement: The recording fills the screen

While a voice note records, the phone app SHALL show it on a screen that covers the whole app, with how long it has recorded, a sound level that follows the microphone, and a way to save and a way to cancel that a person can not confuse. A tap anywhere but the cancel control, or the phone's back gesture, SHALL save the voice note; the cancel control at the top right SHALL keep nothing. The sound level SHALL be used only to draw the screen and SHALL NOT be kept or sent.

#### Scenario: Tap anywhere saves
- **WHEN** a voice note records and the person taps the middle of the screen
- **THEN** the recording screen closes and the voice note is saved, as a tap saves it today

#### Scenario: The X keeps nothing
- **WHEN** a voice note records and the person taps the X at the top right
- **THEN** the recording screen closes, and no note and no recording are kept

### Requirement: A watch recording becomes a voice note

The phone app SHALL keep each recording its paired Apple Watch hands it as a voice note, at the time the person saved it on the watch, with no place, and SHALL write its words on the phone by the same rules as a held voice note: no speech service on any network, and the same failed state and **Try again**. When it finds no words in a watch recording, it SHALL keep the note with its recording, show that no words were heard, and SHALL NOT send it; it SHALL NOT delete a watch note on its own. It SHALL keep the note at once when the app runs, and else the next time it opens. The recording SHALL stay on the phone, and only the note's words SHALL be sent, only while sending is on.

#### Scenario: A watch note while the app runs
- **WHEN** the phone app is open, the speech model is on the phone, and the watch hands it a recording of a sentence
- **THEN** a voice note shows in *Notes*, and under its *Voice* filter, at once, and its words fill in

#### Scenario: A watch note while the app is closed
- **WHEN** the watch hands a recording while the phone app is closed
- **THEN** the next time the app opens, the note shows once, with the watch's save time, and its words are written

#### Scenario: A watch note with no words
- **WHEN** the watch hands a recording in which the phone finds no words
- **THEN** the note stays in *Notes* as *Voice note*, its row shows a microphone, its length and *No words heard* with no tag, its page has the voice player, and nothing is sent
