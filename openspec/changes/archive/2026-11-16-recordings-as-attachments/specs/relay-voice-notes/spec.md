## MODIFIED Requirements

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

## REMOVED Requirements

### Requirement: The recording stays on the phone

**Reason**: A recording now goes with its note like any other file, as the person asked, so it can play on the web page and the Mac and reach their webhooks.

**Migration**: See *A recording goes to the person's space like a file*. Recordings of voice notes made before the update go to the space too, while sending is on.

## ADDED Requirements

### Requirement: A recording goes to the person's space like a file

While sending is on, the phone app SHALL send each recording in a note to the person's own space as one of the note's files, sealed as any file is, with its transcript and its length. It SHALL send nothing while sending is off. A note with a recording whose words are still being written SHALL wait on the phone until they are written or have failed; a failed recording SHALL go with no transcript, and its transcript SHALL follow when **Try again** writes it. The note's text SHALL hold only the words the person typed or gave.

#### Scenario: A voice note with sending on
- **WHEN** sending is on and a held voice note's words are written
- **THEN** the person's space gets the note with an empty text and one file, the recording, with its transcript and its length

#### Scenario: Sending off
- **WHEN** sending is off and the person records a voice note
- **THEN** the note and its recording stay only on the phone, and no request leaves it

### Requirement: A mic in a note adds a recording

The note page on a phone SHALL have a mic button that records into the open note, on the same full-screen recording screen as a held *New note*: a tap saves and the X keeps nothing. Each saved recording SHALL show as its own card at the bottom of the note, after the note's words, with its photos, files and other added recordings in the order they were added, as an added photo does, and its transcript SHALL be written on the phone as for a held voice note. A recording with no words found SHALL stay in the note and show that no words were heard. The mic SHALL NOT show for a note that came from another device, as *Attach* does not, and SHALL refuse a recording once the note holds 10 files, with a message.

#### Scenario: A second recording
- **WHEN** the person opens a voice note with one recording and typed notes, taps the mic, says a sentence and taps the screen
- **THEN** the first recording stays at the top, the new card shows under the typed notes, and its transcript fills in

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
