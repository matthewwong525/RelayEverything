## ADDED Requirements

### Requirement: The watch records a voice note

The Relay Everything watch app SHALL record a voice note when the person taps its mic button, SHALL show that it is recording with the time and the sound level, SHALL save on a tap anywhere on the screen, and SHALL keep nothing on the *X*. A recording shorter than one second SHALL keep nothing, and a recording SHALL stop and save itself at 5 minutes. The watch app SHALL ask for the microphone only on the first tap, and SHALL say how to allow it when the person refused.

#### Scenario: Tap, talk, tap
- **WHEN** the person taps *Talk*, says a sentence and taps the screen
- **THEN** the watch buzzes, shows *Saved*, and holds one note to hand to the iPhone

#### Scenario: Cancel
- **WHEN** the person taps *Talk*, talks, and taps the *X*
- **THEN** the watch keeps no recording and hands nothing to the iPhone

### Requirement: The watch hands notes only to its paired iPhone

The watch app SHALL send each saved recording only to its paired iPhone's Relay Everything app, and SHALL NOT send a recording, or any note, to Relay Everything, Apple or any other network service. While the iPhone is not reachable, each note SHALL wait on the watch, SHALL survive the watch app closing and the watch restarting, and SHALL go when the iPhone is reachable again. The watch SHALL show how many notes wait, and SHALL delete a recording only after the iPhone says it kept the note. The same note SHALL never be kept twice on the iPhone.

#### Scenario: iPhone in another room
- **WHEN** the person saves two notes while the iPhone is out of reach, and later comes back near it
- **THEN** the watch shows *2 notes wait for your iPhone* until then, and both notes then show once each on the iPhone

#### Scenario: Signed out with no signal
- **WHEN** the iPhone app is signed out and has no connection, and the person saves a note on the watch
- **THEN** the note reaches the iPhone and no request leaves either device

### Requirement: The watch face and Action button start a note

The watch app SHALL offer a watch face button that opens the app already recording, and SHALL offer a *Start a voice note* shortcut that the Apple Watch Ultra's Action button can run to do the same.

#### Scenario: From the watch face
- **WHEN** the person taps the Relay Everything button on their watch face
- **THEN** the watch app opens recording, with no further tap
