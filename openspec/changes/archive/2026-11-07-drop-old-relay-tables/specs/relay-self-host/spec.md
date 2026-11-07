## MODIFIED Requirements

### Requirement: An update keeps the person's data

Asking the AI to update an install SHALL bring in the latest Relay code, apply its database changes, and put the new server live, and SHALL keep every note, recording, sample, point, chat and device key in the person's space. A database change that fails SHALL leave the old server live. An install from before spaces SHALL get no move of its old data: its update removes the old shared tables.

#### Scenario: An update with a new table
- **WHEN** a person updates an install and the new code adds a table
- **THEN** the table is made, the new server goes live, and every earlier note and key still works

#### Scenario: A failed database change
- **WHEN** a database change fails during an update
- **THEN** the old server stays live and the AI reports the failure
