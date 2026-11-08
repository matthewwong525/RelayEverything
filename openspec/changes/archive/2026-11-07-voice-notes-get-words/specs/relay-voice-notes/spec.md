## MODIFIED Requirements

### Requirement: A held voice note becomes a note with words

The phone app SHALL record while the person holds the voice button, SHALL write the recording's words on the phone with no speech service on any network, and SHALL show the note in the timeline at once, with its words when they are ready. It SHALL work with no signal and with sending off. When the words fail, or are not written within 2 minutes or the recording's length if longer, the note SHALL keep its recording, SHALL say that the words did not come, and SHALL offer **Try again**; it SHALL NOT show *Writing the words…* after that.

#### Scenario: A voice note in airplane mode
- **WHEN** the speech model is on the phone, the phone has no connection, and the person holds the button, says a sentence and lets go
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
