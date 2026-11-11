## MODIFIED Requirements

### Requirement: Shortcuts can add a note with text and files

On an iPhone with iOS 16 or later, the Relay Everything app SHALL give Apple Shortcuts and Siri an *Add a note* action that takes words, files, or both, and runs without opening the app. The note SHALL be kept on the phone and handled as a note made in the app: it adds a location point while location history is on, and is sent with its files only while sending is on. The action SHALL give the new note back, with no place. An action with no words and no files SHALL ask for the words when the person can answer, as with Siri, and otherwise SHALL fail with a message and keep nothing.

#### Scenario: A screenshot automation with sending on
- **WHEN** an automation passes a new screenshot and the words *bug in checkout* to *Add a note*, and sending is on
- **THEN** the note shows in the app's timeline with the picture, and reaches the person's space with its file within a minute

#### Scenario: The same action with sending off
- **WHEN** sending is off and a shortcut runs *Add a note*
- **THEN** the note is kept on the phone and the app makes no network request
