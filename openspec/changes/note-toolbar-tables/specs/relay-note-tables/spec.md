## ADDED Requirements

### Requirement: Add and edit a table in a note

*Table* in the bar over the keyboard, in the top bar of the browser and the Mac, or ⌥⌘T, SHALL add a table with 2 columns and 2 rows at the cursor, with the cursor in its first cell. A cell SHALL hold plain words. Return in a cell SHALL go to the cell below, and in the last row SHALL add a row. On a computer, Tab SHALL go to the next cell and Shift+Tab to the one before, and Tab in the last cell SHALL add a row. While the cursor is in a cell, a handle SHALL show above its column and at the left of its row: the column's offers *Add column before*, *Add column after* and *Delete column*, and the row's offers *Add row above*, *Add row below* and *Delete row*. *Table* with the cursor in a table SHALL offer *Convert to text* and *Delete table*. A table wider than the page SHALL scroll sideways inside the note. One Undo SHALL take back each table change.

#### Scenario: Add a table and fill it
- **WHEN** the person taps *Table*, types *Stop*, presses Return and types *Toronto*
- **THEN** the note shows a table with *Stop* in the first cell and *Toronto* in the cell below it

#### Scenario: Add a column
- **WHEN** the cursor is in the first column and the person picks *Add column after* from the column's handle
- **THEN** an empty column shows between the first and second columns, and every row keeps its words

### Requirement: A table is kept as a Markdown table

A table SHALL be kept in the note's words as a Markdown table, its first row as the table's head row, so the server, the AI connector, the API and webhooks read rows and columns. A `|` in a cell SHALL be kept as `\|`. A note whose words hold a Markdown table SHALL open with it as a table, and SHALL keep its words byte for byte when the person changes nothing. *Convert to text* SHALL turn each row into a line of its cells' words, split by tabs.

#### Scenario: A table sent to a webhook
- **WHEN** a note with a table of *Stop*, *Date* over *Toronto*, *Nov 20* is sent
- **THEN** its words read `| Stop | Date |`, `| --- | --- |` and `| Toronto | Nov 20 |`

#### Scenario: A table from Claude
- **WHEN** a note made through the AI connector holds a Markdown table and the person opens it on the phone
- **THEN** it shows as a table, and leaving it unchanged does not send it again
