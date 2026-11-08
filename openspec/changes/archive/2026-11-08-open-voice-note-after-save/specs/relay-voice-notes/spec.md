## ADDED Requirements

### Requirement: A saved voice note opens its page

When the person taps to save a voice note, from a hold on *New note* or from Shortcuts and the Action button, the phone app SHALL open the new note's page at once, over the page that was open, and its words SHALL fill in on that page. Back SHALL return to the page that was open before. *Cancel*, a recording too short to keep, a recording that stops itself at its longest length, and a note the phone could not keep SHALL open no page.

#### Scenario: Tap to save
- **WHEN** the person holds *New note*, talks, and taps the screen
- **THEN** the note's page opens, shows *Writing the words…*, and then shows the words; Back shows the notes list

#### Scenario: Cancel
- **WHEN** the person taps *Cancel* on the listening card
- **THEN** no note is kept and no page opens
