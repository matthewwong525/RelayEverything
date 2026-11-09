## MODIFIED Requirements

### Requirement: One button writes or talks

The notes list SHALL have one *New note* button. A press shorter than half a second SHALL open the page to write a note. A press held for half a second SHALL start a voice note, as the voice notes requirements say. The button SHALL show the hold's progress while it is pressed, and SHALL show a *Hold to talk* tip until the person's first voice note starts. A person who uses a screen reader SHALL be able to start a voice note from the same button.

#### Scenario: A tap writes

- **WHEN** the person taps *New note*
- **THEN** the page to write a note opens with the keyboard up, and nothing records

#### Scenario: The tip goes after the first voice note

- **WHEN** a person who has never made a voice note opens the notes list, then holds *New note* and saves a voice note
- **THEN** the *Hold to talk* tip shows on the first visit, and does not show again, also after the app restarts
