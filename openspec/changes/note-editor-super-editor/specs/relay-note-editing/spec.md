## ADDED Requirements

### Requirement: A triple-click selects a line

In a note, three quick clicks at the same place SHALL select the whole line under the pointer, on the Mac app and the web page; three quick taps SHALL do the same on a phone. The line SHALL run from the line break before the pointer to the next line break, so a line inside a list item selects alone, without the item's other lines. One click SHALL still place the cursor, and two SHALL still select a word.

#### Scenario: Select a list item's line
- **WHEN** the person triple-clicks on `Star Kit — 280 kits · Due today (late)`, a numbered item with a `Why:` line under it
- **THEN** the item's words are selected, and the `Why:` line is not

#### Scenario: Double-click still selects a word
- **WHEN** the person double-clicks on `Kit`
- **THEN** only `Kit` is selected

### Requirement: A pasted list keeps its shape

A paste of plain text SHALL keep each list as it was copied. Numbered items SHALL show the numbers in order, counting on past lines that belong to an item. A list whose first item is indented by up to three spaces, with no list above it, SHALL start at the first level, not as a sub-list. A line indented under a list item SHALL stay in that item, on its own line under the item's words, and SHALL be kept so in the note's Markdown. Only an item indented past its list's own level SHALL become a sub-list.

#### Scenario: Paste a plan with Why lines
- **WHEN** the person pastes `Assembly`, then `  1. Garden Kit Box` with `     Why: Pallet leaves Fri` under it, then `  2. Star Kit` with its own `Why:` line
- **THEN** the note shows *Assembly*, then items numbered 1 and 2, each with its `Why:` line under its words, and no item shows a letter

#### Scenario: A real sub-list stays a sub-list
- **WHEN** the person pastes `1. Pack`, then `   - Tape` and `   - Labels` one level in, then `2. Ship`
- **THEN** *Tape* and *Labels* show as a sub-list under *Pack*, and *Ship* shows as 2

### Requirement: Even spacing between lines

A note SHALL show the same space above every line of body text: a paragraph, a list item, a checklist item, a quote, and a line under a list item. A Title, Heading or Subheading SHALL have the same space above it in every note. One empty line SHALL add one fixed gap. This SHALL hold on the phone, the Mac app and the web page, and for a note made by typing or by a paste.

#### Scenario: A Why line takes a line's space
- **WHEN** a note shows a numbered item with a `Why:` line under it, and a next item
- **THEN** the space above the `Why:` line and above the next item equals the space between two plain lines
