## MODIFIED Requirements

### Requirement: Tool bars match Apple Notes

While the keyboard is up, a tool bar SHALL float close above it, about 6 points over its top, with *Text styles*, *Checklist*, *Attach* and, on a phone, *Record*, and the top SHALL show back, share, ⋯ and a done button that closes the keyboard. The page SHALL keep the cursor in view above the floating tool bar, never under it and never under the top edge, when the person taps into the note, as they type, and when the cursor moves, such as by Undo. While the keyboard is down, the bottom SHALL show *Checklist*, *Attach*, on a phone *Record*, and a compose button that opens a new note. *Record* SHALL record into the open note, as the voice notes requirements say. The ⋯ menu SHALL offer *Pin Note* or *Unpin Note*, *Find in Note* on a phone, *Copy*, and *Delete*. It SHALL open under its button with its right edge in line with the button's, fully inside the screen with a margin, and with round corners. Every button SHALL have a name a screen reader says.

#### Scenario: Done closes the keyboard
- **WHEN** the person is editing and taps the done button
- **THEN** the keyboard closes, the change is kept, and the bottom bar with *Record* and the compose button shows

#### Scenario: No mic on the web page
- **WHEN** the person opens a note on the Relay Everything web page or in the Mac app
- **THEN** the bars show no *Record* button

#### Scenario: The ⋯ menu fits on a small phone
- **WHEN** the person taps ⋯ on a note's page on a 375-point-wide phone
- **THEN** the menu shows *Copy* under the ⋯ button, its right edge in line with the button and inside the screen, with no part cut off

#### Scenario: Typing at the end of a long note
- **WHEN** the person taps at the end of a note longer than the screen and types a line
- **THEN** the page scrolls so the line with the cursor shows above the floating tool bar

