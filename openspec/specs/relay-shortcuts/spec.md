# relay-shortcuts Specification

## Purpose
Let a person add notes with words and files, get notes, and start a voice note from Apple Shortcuts, Siri and automations, through the Relay Everything iPhone app.

## Requirements

### Requirement: Shortcuts can add a note with text and files

On an iPhone with iOS 16 or later, the Relay Everything app SHALL give Apple Shortcuts and Siri an *Add a note* action that takes words, files, or both, and runs without opening the app. The note SHALL be kept on the phone and handled as a note made in the app: pinned when *Pin notes* is on, and sent with its files only while sending is on. The action SHALL give the new note back. An action with no words and no files SHALL fail with a message and keep nothing.

#### Scenario: A screenshot automation with sending on
- **WHEN** an automation passes a new screenshot and the words *bug in checkout* to *Add a note*, and sending is on
- **THEN** the note shows in the app's timeline with the picture, and reaches the person's space with its file within a minute

#### Scenario: The same action with sending off
- **WHEN** sending is off and a shortcut runs *Add a note*
- **THEN** the note is kept on the phone and the app makes no network request

### Requirement: Shortcuts can get notes from the phone

The app SHALL give Shortcuts a *Get notes* action that returns the phone's notes, newest first, limited by a count, words they hold, or a start time. Each result SHALL carry the note's words, time, place, kind and files. The action SHALL read only the phone and SHALL make no network request.

#### Scenario: Today's notes by email
- **WHEN** a shortcut gets notes since the start of today and passes them to *Send Email*
- **THEN** the email holds each of today's notes, and no server is asked

### Requirement: Shortcuts can start a voice note

The app SHALL give Shortcuts and the Action button a *Start a voice note* action that opens the app and starts recording at once. The recording SHALL stop and save when the person taps *Stop*, and keep nothing on *Cancel*. With no speech model on the phone, the app SHALL ask to get it, as the hold-to-talk button does.

#### Scenario: The Action button
- **WHEN** the person presses the Action button set to *Start a voice note*, talks, and taps *Stop*
- **THEN** a voice note is saved and its words are written on the phone

### Requirement: Older iPhones keep the app

The app SHALL still install and run on iOS 15, without the Shortcuts actions.

#### Scenario: An iPhone on iOS 15
- **WHEN** the person opens the app on iOS 15
- **THEN** every other part of the app works, and Shortcuts lists no Relay Everything action
