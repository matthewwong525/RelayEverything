## ADDED Requirements

### Requirement: The cursor shows on any page

On a computer, the typing cursor in a note SHALL show in the colour of the note's words, so it shows on a light page and on a dark page alike.

#### Scenario: A dark page
- **WHEN** the web page or the Mac app is in dark mode and the person clicks into a note
- **THEN** a light cursor blinks where they clicked

### Requirement: Tab moves every selected line

With several lines selected in a note, Tab SHALL move every selected line one level in, and Shift+Tab SHALL move every selected line one level out. The words SHALL stay as they were, and the selection SHALL stay.

#### Scenario: Three list items
- **WHEN** the person selects three bulleted items and presses Tab, then Shift+Tab
- **THEN** all three move one level in, then all three move back out, and the note's words are the same as before
