## ADDED Requirements

### Requirement: The text menu is the iPhone's own

While the person edits a note on an iPhone that can show the system text menu (iOS 16 and later), a hold, a selection, or a tap on the cursor SHALL show the iPhone's own text menu, with the standard items that fit the selection: *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Search Web* and *Share*. A tap on *Paste* SHALL put in the words from the clipboard at the cursor as plain text, in the note's own style, with no *Allow Paste?* question, also for words copied in another app. A tap on the blinking cursor SHALL open the menu, and a second tap SHALL close it; a tap anywhere else SHALL move the cursor there, as before. While the person drags the cursor or a selection handle, a magnifier SHALL show the words under the finger. Where the iPhone's own menu can't show (an older iPhone or Android), the app SHALL show its own menu with the same actions, and the browser SHALL keep the browser's own menu.

#### Scenario: Paste words from another app

- **WHEN** the person copies `Buy oat milk` in Safari, opens a note, and taps *Paste* in the menu after a hold in the words
- **THEN** `Buy oat milk` is in the note at the cursor as plain text, in the note's style, and no *Allow Paste?* question showed

#### Scenario: Tap the cursor to open the menu

- **WHEN** the person types in a note and taps on the blinking cursor
- **THEN** the iPhone's own menu shows *Paste* above the cursor, and a second tap on the cursor closes it
