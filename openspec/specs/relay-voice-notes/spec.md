# relay-voice-notes Specification

## Purpose
Let a person talk a note into the Relay phone app and get its words written on the phone itself, with their voice never leaving the phone.

## Requirements

### Requirement: A held voice note becomes a note with words

The phone app SHALL start recording when the person holds *New note* for half a second, SHALL keep recording after the finger lifts, and SHALL stop and save when the person taps anywhere on the screen. It SHALL keep the recording in the new note, SHALL write the recording's words on the phone with no speech service on any network, and SHALL keep those words as the recording's transcript, not as the note's text. It SHALL show the note in the timeline at once, with the transcript when it is ready. It SHALL work with no signal and with sending off. When the words fail, or are not written within 2 minutes or the recording's length if longer, the recording SHALL stay in the note, its card SHALL say that the words did not come and give the reason, and SHALL offer **Try again**; it SHALL NOT show *Writing the words…* after that. The reason SHALL stay on the phone.

#### Scenario: A voice note in airplane mode
- **WHEN** the speech model is on the phone, the phone has no connection, and the person holds *New note* until it turns into a mic, lets go, says a sentence and taps the screen
- **THEN** the note shows at once with an empty text and one recording, the recording's transcript fills in, and no request leaves the phone

#### Scenario: The words fail
- **WHEN** writing a recording's words fails with any error
- **THEN** the note keeps its recording, the recording's card shows *The words did not come. Your recording is safe.*, a line with the reason, and **Try again**

#### Scenario: The app closes before the words are written
- **WHEN** the app is closed while a voice note's words are being written
- **THEN** the next time the app opens, it writes them from the kept recording

#### Scenario: The words take too long
- **WHEN** a voice note's words are not written within the time limit
- **THEN** the app stops the writing and the note shows the same failed state, with the time limit as the reason

#### Scenario: Try again
- **WHEN** the person taps **Try again** on a failed note, comes back to the app, or opens the app again
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

The phone app SHALL keep each recording its paired Apple Watch hands it as a new note that holds that recording, at the time the person saved it on the watch, with no place, and SHALL write the recording's transcript on the phone by the same rules as a held voice note: no speech service on any network, and the same failed state and **Try again**. When it finds no words in a watch recording, it SHALL keep the note with its recording and show that no words were heard; it SHALL NOT delete a watch note on its own. It SHALL keep the note at once when the app runs, and else the next time it opens. The note and its recording SHALL go to the person's space only while sending is on.

#### Scenario: A watch note while the app runs
- **WHEN** the phone app is open, the speech model is on the phone, and the watch hands it a recording of a sentence
- **THEN** a note with that recording shows in *Notes*, and under its *Voice* filter, at once, and the recording's transcript fills in

#### Scenario: A watch note with no words
- **WHEN** the watch hands a recording in which the phone finds no words
- **THEN** the note stays in *Notes* as *Voice note*, its row shows a microphone and its length, its page has the recording's card with *No words heard*, and with sending on the recording goes to the person's space with no transcript

#### Scenario: A watch note while the app is closed
- **WHEN** the watch hands a recording while the phone app is closed
- **THEN** the next time the app opens, the note shows once, with the watch's save time, and its words are written

### Requirement: The words are written when the app is not on the screen

The phone app SHALL write a voice note's words when the app runs but is not on the screen, such as when a watch note starts it, when the phone is locked, or when the person leaves the app while the words are written. A write that fails SHALL NOT make the write of a later note fail. When the iPhone stops the app before the words are written, the app SHALL write them the next time it runs.

#### Scenario: A watch note with the phone locked
- **WHEN** the iPhone is locked, the speech model is on the phone, and the watch hands the app a recording of a sentence
- **THEN** the note gets its words with the app not opened, and with sending on the words are sent

#### Scenario: A note after a failed note
- **WHEN** writing one voice note's words fails, and the person then saves a second voice note with a sentence in it
- **THEN** the second note gets its words

### Requirement: A recording goes to the person's space like a file

While sending is on, the phone app SHALL send each recording in a note to the person's own space as one of the note's files, sealed as any file is, with its transcript and its length. It SHALL send nothing while sending is off. A note with a recording whose words are still being written SHALL wait on the phone until they are written or have failed; a failed recording SHALL go with no transcript, and its transcript SHALL follow when **Try again** writes it. The note's text SHALL hold only the words the person typed or gave.

#### Scenario: A voice note with sending on
- **WHEN** sending is on and a held voice note's words are written
- **THEN** the person's space gets the note with an empty text and one file, the recording, with its transcript and its length

#### Scenario: Sending off
- **WHEN** sending is off and the person records a voice note
- **THEN** the note and its recording stay only on the phone, and no request leaves it

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

### Requirement: Voice notes move to the new shape

On the first open after the update, the phone app SHALL move each voice note it keeps to the new shape: its recording becomes the note's first file and sits at the top of the note, its words become that recording's transcript, and the note's text becomes empty. A note waiting for its words, or whose words failed, SHALL keep that state on its recording. The move SHALL keep each note's time, pin and id, and SHALL run once. With sending on, each moved note SHALL go to the person's space as a change, with its recording.

#### Scenario: An old voice note
- **WHEN** the phone holds a voice note from before the update with the words *Call the fab* and the app opens
- **THEN** the note's page shows one recording card with the transcript *Call the fab*, and an empty note under it

#### Scenario: The second open
- **WHEN** the app opens again after the move
- **THEN** nothing moves again and no note is sent again
