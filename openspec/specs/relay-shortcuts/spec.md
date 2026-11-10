# relay-shortcuts Specification

## Purpose
Let a person add notes with words and files, get notes, and start a voice note from Apple Shortcuts, Siri and automations, through the Relay Everything iPhone app.

## Requirements

### Requirement: Shortcuts can add a note with text and files

On an iPhone with iOS 16 or later, the Relay Everything app SHALL give Apple Shortcuts and Siri an *Add a note* action that takes words, files, or both, and runs without opening the app. The note SHALL be kept on the phone and handled as a note made in the app: pinned when *Pin notes* is on, and sent with its files only while sending is on. The action SHALL give the new note back. An action with no words and no files SHALL ask for the words when the person can answer, as with Siri, and otherwise SHALL fail with a message and keep nothing.

#### Scenario: A screenshot automation with sending on
- **WHEN** an automation passes a new screenshot and the words *bug in checkout* to *Add a note*, and sending is on
- **THEN** the note shows in the app's timeline with the picture, and reaches the person's space with its file within a minute

#### Scenario: The same action with sending off
- **WHEN** sending is off and a shortcut runs *Add a note*
- **THEN** the note is kept on the phone and the app makes no network request

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

### Requirement: Shortcuts can get notes from the phone

The app SHALL give Shortcuts a *Get notes* action that returns the phone's notes, newest first, limited by a count, words they hold, or a start time. Each result SHALL carry the note's words, time, place, kind and files. The action SHALL read only the phone and SHALL make no network request.

#### Scenario: Today's notes by email
- **WHEN** a shortcut gets notes since the start of today and passes them to *Send Email*
- **THEN** the email holds each of today's notes, and no server is asked

### Requirement: Shortcuts can start a voice note

The app SHALL give Shortcuts and the Action button a *Start a voice note* action that opens the app and starts recording at once, on the same full-screen recording as holding *New note*. The recording SHALL stop and save when the person taps anywhere on the screen, and keep nothing on the X. With no speech model on the phone, the app SHALL ask to get it, as holding *New note* does.

#### Scenario: The Action button
- **WHEN** the person presses the Action button set to *Start a voice note*, talks, and taps the screen
- **THEN** a voice note is saved and its words are written on the phone

### Requirement: Older iPhones keep the app

The app SHALL still install and run on iOS 15, without the Shortcuts actions.

#### Scenario: An iPhone on iOS 15
- **WHEN** the person opens the app on iOS 15
- **THEN** every other part of the app works, and Shortcuts lists no Relay Everything action

### Requirement: Siri takes a spoken note in one go

On an iPhone whose Siri can fill an app action's words from the request, such as the new Siri on iOS 27 with Apple Intelligence, the person SHALL be able to say a note and its words in one sentence, and Siri SHALL keep those words as one note with no question. On other iPhones, when Siri runs *Add a note* with no words and no files, the app SHALL ask for the words and keep the answer. Either way, the note SHALL be kept as a typed note is, and Siri SHALL say the note was saved. A shortcut that gives words or files SHALL run with no question, as before.

#### Scenario: One sentence on the new Siri
- **WHEN** the person says *Hey Siri, take a note in Relay, buy milk on the way home* on an iPhone with the new Siri
- **THEN** Siri asks nothing, says it is saved, and the app shows a note *buy milk on the way home*, sent only while sending is on

#### Scenario: An older Siri
- **WHEN** the person says *Hey Siri, take a note in Relay* on an iPhone without the new Siri
- **THEN** Siri asks for the note, and keeps the spoken answer as one note

### Requirement: Siri knows the app by a short name

Siri SHALL start the app's actions when the person names the app *Relay*, as well as *Relay Everything*. The app's name on the Home Screen, in the App Store and in all written text SHALL stay *Relay Everything*.

#### Scenario: The short name
- **WHEN** the person says *Hey Siri, add a note to Relay*
- **THEN** Siri runs the Relay Everything app's *Add a note*
