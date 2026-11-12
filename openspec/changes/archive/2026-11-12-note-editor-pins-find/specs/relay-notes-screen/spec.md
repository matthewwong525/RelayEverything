## MODIFIED Requirements

### Requirement: Notes are listed by day

The phone app SHALL list the phone's notes newest first, in groups headed *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, and then by month, after the *Pinned* part when one shows. A pinned note SHALL show only in *Pinned*, not in its day group. Each note SHALL show its first line, then its time and the start of the rest of its words. A voice note SHALL also show a microphone and its length before the words. A row SHALL show no *Voice* or *Typed* tag and no *Sent*; while sending is on, a note that waits SHALL say *Waiting to send*.

#### Scenario: Notes from three days

- **WHEN** the phone holds a note from today, one from yesterday and one from four days ago
- **THEN** each shows under *Today*, *Yesterday* and *Previous 7 days*, newest first

#### Scenario: A sent note and a waiting note

- **WHEN** sending is on, one note is sent and one waits
- **THEN** the sent note's row says nothing about sending, and the other row says *Waiting to send*

#### Scenario: A pinned note from today

- **WHEN** the phone holds two notes from today and one of them is pinned
- **THEN** the pinned note shows under *Pinned* at the top, and *Today* holds only the other one
