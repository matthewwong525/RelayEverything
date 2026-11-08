## MODIFIED Requirements

### Requirement: An update keeps the person's data

Asking the AI to update an install SHALL bring in the latest Relay code, apply its database changes, and put the new server live, and SHALL keep every note, recording, sample, point, chat and device key in the person's space. A database change that fails SHALL leave the old server live. An install from before spaces SHALL get no move of its old data: its update removes the old shared tables. An install made before the setup tool moved inside the app SHALL update with its own settings and key, with no step from the person.

#### Scenario: An update with a new table
- **WHEN** a person updates an install and the new code adds a table
- **THEN** the table is made, the new server goes live, and every earlier note and key still works

#### Scenario: A failed database change
- **WHEN** a database change fails during an update
- **THEN** the old server stays live and the AI reports the failure

#### Scenario: An install made before the tool moved
- **WHEN** a person who installed with the old top-level setup folder pulls the latest code and updates
- **THEN** the update finds their settings and Cloudflare key, keeps their server's names and sign-up choice, and puts the new server live
