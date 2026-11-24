# Spec Delta

## MODIFIED Requirements

### Requirement: The text menu is the iPhone's own

While the person edits a note, a hold, a selection, or a tap on the cursor SHALL show the system's own text menu: on an iPhone, the iPhone's own menu, with the standard items that fit the selection, such as *Paste*, *Copy*, *Cut*, *Select All*, *Look Up*, *Translate*, *Search Web* and *Share*; on Android, Android's own menu; on the Mac, the Mac's own right-click menu; and in the browser, the browser's own menu. A tap on *Paste* SHALL put in the words from the clipboard at the cursor, with the formatting the note can show (see *A paste keeps its formatting*), with no *Allow Paste?* question, also for words copied in another app. A tap on the blinking cursor SHALL open the menu, and a second tap SHALL close it; a tap anywhere else SHALL move the cursor there, as before. While the person drags the cursor or a selection handle on a phone, the system's own magnifier SHALL show the words under the finger. The app SHALL NOT draw its own copy of the text menu, the handles or the magnifier.

#### Scenario: Paste words from another app

- **WHEN** the person copies `Buy oat milk` in Safari, opens a note, and taps *Paste* in the menu after a hold in the words
- **THEN** `Buy oat milk` is in the note at the cursor, in the note's style, and no *Allow Paste?* question showed

#### Scenario: Tap the cursor to open the menu

- **WHEN** the person types in a note and taps on the blinking cursor
- **THEN** the iPhone's own menu shows *Paste* above the cursor, and a second tap on the cursor closes it

## ADDED Requirements

### Requirement: Text editing is the system's own

In a note, the cursor, the selection handles, autocorrect, word suggestions, text replacements, dictation and the space-bar cursor SHALL be the ones the platform gives its own text views, on the iPhone, Android and the Mac. The Mac's spell check and the browser's spell check SHALL mark a misspelt word. On the web page, the note's words SHALL be text of the page, so the browser's own selection, find and spell check work on them.

#### Scenario: Autocorrect on an iPhone
- **WHEN** the person types `teh ` in a note on an iPhone
- **THEN** the iPhone corrects it to `the `, as it does in Notes

#### Scenario: Find on the web page
- **WHEN** a note is open on the web page and the person uses the browser's find for a word in it
- **THEN** the browser marks that word in the note

### Requirement: A note opens fast and with no flash

A note's page SHALL show the note's words within half a second of the tap that opens it on a recent phone, and its first frame SHALL be in the page's own colours, with no white frame in dark mode. A new note SHALL open with the keyboard up and the cursor in its first line, with no tap.

#### Scenario: Open a note in dark mode
- **WHEN** the phone is in dark mode and the person taps a note in the list
- **THEN** the note page shows dark from its first frame, and the words show within half a second

#### Scenario: A new note
- **WHEN** the person taps *New note*
- **THEN** the note page opens with the keyboard up and the cursor in the title line

### Requirement: Screen readers read and edit a note

With VoiceOver or TalkBack on, the person SHALL be able to move through a note's words by line and by word, hear each style that is named, such as a heading or a ticked checklist item, and type and delete words, as in a text view of the system. A checklist circle SHALL say whether it is ticked, and a double tap SHALL tick or untick it.

#### Scenario: Hear a checklist
- **WHEN** VoiceOver is on and the person moves to an open checklist item *Buy oat milk*
- **THEN** VoiceOver says the words and that the item is not ticked, and a double tap on its circle ticks it
