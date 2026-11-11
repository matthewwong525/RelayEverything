## ADDED Requirements

### Requirement: Keeping a note adds one location point

While location history is on, keeping a note made now in the app, or by Shortcuts or Siri while the app runs, SHALL take one fix and add it to location history as one point at the note's time, with its street name when the phone finds one. The point SHALL go as every other point does: where points go, by the person's *What to send* choice, so with *Only stays and trips* it SHALL join the stay or trip and no point SHALL go. There SHALL be no setting for it. While location history is off, the phone SHALL read no place for a note. A note that reaches the app later, such as from the share card, the watch, or a shortcut that ran while the app was closed, SHALL add no point, as the phone's fix would be at another time. A note SHALL be kept and sent without waiting for its fix.

#### Scenario: A note with location history on
- **WHEN** location history is on and the person keeps a note at 9:41 on Queen St W
- **THEN** the note holds no place, and the phone's next send gives location history one point at 9:41 named Queen St W

#### Scenario: Location history off
- **WHEN** location history is off and the person keeps a note
- **THEN** the phone asks for no location and reads no place, and no point is kept
