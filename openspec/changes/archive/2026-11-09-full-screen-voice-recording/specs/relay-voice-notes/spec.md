## ADDED Requirements

### Requirement: The recording fills the screen

While a voice note records, the phone app SHALL show it on a screen that covers the whole app, with how long it has recorded, a sound level that follows the microphone, and a way to save and a way to cancel that a person can not confuse. A tap anywhere but the cancel control, or the phone's back gesture, SHALL save the voice note; the cancel control at the top right SHALL keep nothing. The sound level SHALL be used only to draw the screen and SHALL NOT be kept or sent.

#### Scenario: Tap anywhere saves
- **WHEN** a voice note records and the person taps the middle of the screen
- **THEN** the recording screen closes and the voice note is saved, as a tap saves it today

#### Scenario: The X keeps nothing
- **WHEN** a voice note records and the person taps the X at the top right
- **THEN** the recording screen closes, and no note and no recording are kept
