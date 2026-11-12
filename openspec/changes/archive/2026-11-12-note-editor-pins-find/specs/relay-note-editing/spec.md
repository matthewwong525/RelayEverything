## MODIFIED Requirements

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float close above it, about 6 points over its top, with *Text styles*, *Checklist* and *Attach*, and the top SHALL show back, share, ⋯ and a done button that closes the keyboard. The page SHALL keep the cursor in view above the floating tool bar, never under it and never under the top edge, when the person taps into the note, as they type, and when the cursor moves, such as by Undo. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach* and a compose button that opens a new note. The ⋯ menu SHALL offer *Pin Note* or *Unpin Note*, *Find in Note* on a phone, *Copy*, and *Delete*. It SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with the compose button shows

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

#### Scenario: Typing at the end of a long note
- **WHEN** the person taps at the end of a note longer than the screen and types a line
- **THEN** the page scrolls so the line with the cursor shows above the floating tool bar

## ADDED Requirements

### Requirement: Undo and Redo while typing

While the keyboard is up and the note has a change since the page opened, the top SHALL show an *Undo* button left of share and ⋯. A tap SHALL take back the last change and keep the keyboard up. After an undo, a *Redo* button SHALL show beside *Undo* and SHALL put the change back; a new change SHALL remove *Redo*. Undo SHALL go back no further than the words the page opened with. An undone change SHALL be kept and sent as any change is.

#### Scenario: Undo a line
- **WHEN** the person opens a note, types *buy milk*, and taps *Undo*
- **THEN** *buy milk* goes, the keyboard stays up, and *Redo* shows beside *Undo*

#### Scenario: Nothing to undo
- **WHEN** the person opens a note and taps into it without a change
- **THEN** the top shows no *Undo* and no *Redo*

### Requirement: Find in Note

On a phone, *Find in Note* in a note's ⋯ menu SHALL show a find bar over the keyboard in place of the tool bar: a field for the words to find, the place of the current match out of all matches, such as *2 of 14*, and up and down buttons. Matching SHALL ignore capital letters. The page SHALL select the current match and scroll it into view; down SHALL go to the next match and up to the one before, each going round at the end. Finding SHALL NOT change the note. ✓, a tap in the note's words, or leaving the page SHALL close the find bar; after a tap in the words, the person edits the note with the tool bar back.

#### Scenario: Step through matches
- **WHEN** a note holds *Train* once and *train* twice, and the person finds *train* and taps down twice
- **THEN** the bar reads *1 of 3*, then *2 of 3*, then *3 of 3*, with each match selected in turn, and the note's words are unchanged

#### Scenario: No match
- **WHEN** the person finds words the note does not hold
- **THEN** the bar reads *No matches* and up and down do nothing
