# Spec Delta

## MODIFIED Requirements

### Requirement: A held voice note becomes a note with words

The phone app SHALL start recording when the person holds *New note* for half a second, SHALL keep recording after the finger lifts, and SHALL stop and save when the person taps anywhere on the screen. It SHALL write the recording's words on the phone with no speech service on any network, and SHALL show the note in the timeline at once, with its words when they are ready. It SHALL work with no signal and with sending off. When the words fail, or are not written within 2 minutes or the recording's length if longer, the note SHALL keep its recording, SHALL say that the words did not come, SHALL give the reason on the note's page, and SHALL offer **Try again**; it SHALL NOT show *Writing the words…* after that. The reason SHALL stay on the phone.

#### Scenario: A voice note in airplane mode
- **WHEN** the speech model is on the phone, the phone has no connection, and the person holds *New note* until it turns into a mic, lets go, says a sentence and taps the screen
- **THEN** the note shows at once, its words fill in, and no request leaves the phone

#### Scenario: The app closes before the words are written
- **WHEN** the app is closed while a voice note's words are being written
- **THEN** the next time the app opens, it writes them from the kept recording

#### Scenario: The words fail
- **WHEN** writing a voice note's words fails with any error
- **THEN** the note keeps its recording, shows *The words did not come. Your recording is safe.*, a line with the reason, and **Try again**, and the app shows a notice once

#### Scenario: The words take too long
- **WHEN** a voice note's words are not written within the time limit
- **THEN** the app stops the writing and the note shows the same failed state, with the time limit as the reason

#### Scenario: Try again
- **WHEN** the person taps **Try again** on a failed note, comes back to the app, or opens the app again
- **THEN** the app writes the words again from the kept recording

## ADDED Requirements

### Requirement: The words are written when the app is not on the screen

The phone app SHALL write a voice note's words when the app runs but is not on the screen, such as when a watch note starts it, when the phone is locked, or when the person leaves the app while the words are written. A write that fails SHALL NOT make the write of a later note fail. When the iPhone stops the app before the words are written, the app SHALL write them the next time it runs.

#### Scenario: A watch note with the phone locked
- **WHEN** the iPhone is locked, the speech model is on the phone, and the watch hands the app a recording of a sentence
- **THEN** the note gets its words with the app not opened, and with sending on the words are sent

#### Scenario: A note after a failed note
- **WHEN** writing one voice note's words fails, and the person then saves a second voice note with a sentence in it
- **THEN** the second note gets its words
