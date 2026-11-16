## ADDED Requirements

### Requirement: A recording plays on the web page

The web page SHALL show each recording in a note as the phone's recording card, with a plain line in place of the sound waves, and its transcript folded to 2 lines. It SHALL play the recording from the person's space once the sound is there; before that, the card SHALL show the transcript and say the recording is still on the phone. The web page SHALL NOT record.

#### Scenario: Play on a computer
- **WHEN** the person opens a voice note on the web page after the phone sent it with its recording
- **THEN** the card shows the transcript, and play plays the recording
