## ADDED Requirements

### Requirement: A recording given to Add a note becomes a voice note

When *Add a note* gets one file and that file is a recording the phone can read, the app SHALL keep the note as a voice note: it shows at once, the phone writes the recording's words, and the note has *Play*, and *Try again* when the words fail. Words given with the recording SHALL come first in the note, and the written words SHALL follow on the next line. With no speech in the recording, a note with given words SHALL keep those words and its recording; a note with no given words SHALL be dropped, as a held voice note with no speech is. The words SHALL be written on the phone, and the note SHALL go to the person's space only while sending is on, after its words are written. A recording given with other files, or one the phone cannot read, SHALL be kept as a plain file. The action SHALL show its files slot in its main line, beside the words.

#### Scenario: A recorded shortcut with a label
- **WHEN** a shortcut runs *Record audio*, then *Add a note* with the words *Note @ 7:07 PM* and the *Recorded Audio*
- **THEN** the app shows a voice note that starts with *Note @ 7:07 PM*, then the written words of the recording, and *Play* plays the recording

#### Scenario: The app is closed
- **WHEN** the same shortcut runs while the Relay Everything app is closed
- **THEN** the voice note is kept on the phone, and its words are written the next time the person opens the app

#### Scenario: A recording with a photo
- **WHEN** *Add a note* gets a recording and a photo
- **THEN** both are kept as plain files on one note, as before
