## ADDED Requirements

### Requirement: On an iPhone, a button acts when the finger lifts

On an iPhone, each round button of the phone app that has a name, such as ⋯, *Undo* or the recording screen's X, SHALL act when the finger lifts, however long the press, as other iPhone apps do. A long press SHALL show no name bubble, on a button or on a picture in a note. Each button SHALL keep its name for VoiceOver. A button with its own hold action, such as *New note*, SHALL keep that action. On Android, a long press SHALL still show the button's name and not act.

#### Scenario: A long press on an iPhone

- **WHEN** a person holds a round button with a name on an iPhone for 1 second, then lifts the finger
- **THEN** the button acts, and no name bubble shows

#### Scenario: A long press on Android

- **WHEN** a person holds the same button on Android for 1 second
- **THEN** its name bubble shows, and the button does not act
