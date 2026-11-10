## MODIFIED Requirements

### Requirement: Shortcuts can add a note with text and files

On an iPhone with iOS 16 or later, the Relay Everything app SHALL give Apple Shortcuts and Siri an *Add a note* action that takes words, files, or both, and runs without opening the app. The note SHALL be kept on the phone and handled as a note made in the app: pinned when *Pin notes* is on, and sent with its files only while sending is on. The action SHALL give the new note back. An action with no words and no files SHALL ask for the words when the person can answer, as with Siri, and otherwise SHALL fail with a message and keep nothing.

#### Scenario: A screenshot automation with sending on
- **WHEN** an automation passes a new screenshot and the words *bug in checkout* to *Add a note*, and sending is on
- **THEN** the note shows in the app's timeline with the picture, and reaches the person's space with its file within a minute

#### Scenario: The same action with sending off
- **WHEN** sending is off and a shortcut runs *Add a note*
- **THEN** the note is kept on the phone and the app makes no network request

## ADDED Requirements

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
