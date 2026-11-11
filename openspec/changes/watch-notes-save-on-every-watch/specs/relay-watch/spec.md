# Spec Delta

## ADDED Requirements

### Requirement: A watch note saves on every Apple Watch that runs the app

The watch app SHALL save a recording, and hold it for the iPhone, on every Apple Watch model that runs watchOS 10 or later, including the models whose apps run with 32-bit numbers (Series 4 to 8, SE, SE 2 and the first Ultra). No value the watch app keeps with a note, such as its time, SHALL depend on the size of a number on the watch model.

#### Scenario: A Series 8
- **WHEN** a person with an Apple Watch Series 8 opens the watch app, says a sentence and taps the screen
- **THEN** the watch shows *Saved*, the app stays open, and the watch holds one note to hand to the iPhone

### Requirement: The watch app opens on the recording screen

When the microphone is allowed or not yet asked for, the watch app SHALL show the recording screen from the first moment it is on screen, each time the person opens it or comes back to it, and SHALL NOT show *Tap to record*, *Saved* or *Not saved* first. *Tap to record* SHALL show only after the person taps the *X*. When the person refused the microphone, the app SHALL open on the screen that says how to allow it.

#### Scenario: Open the app
- **WHEN** the person opens the watch app with the microphone allowed
- **THEN** the first screen is the recording screen, with the clock at 0:00, and no other screen shows before it

#### Scenario: Come back after a save
- **WHEN** the person saves a note with a tap, leaves the app on *Saved*, and opens it again
- **THEN** the first screen is the recording screen, not *Saved*
