# relay-agent-database Specification

## Purpose
TBD - created by archiving change relay-agent-database. Update Purpose after archive.

## Requirements

### Requirement: Each person's agents have their own database
Relay Everything SHALL give each person a second database, apart from their space, only for the agents on their computers. A computer key SHALL be able to make any table there, and to send it any database command, alone or as several in one all-or-none step. Relay Everything's own tables SHALL NOT be in that database, so no command sent to it SHALL read or change a note, health record, place, chat, fact or any other synced record. No other key SHALL reach it.

#### Scenario: An agent makes a table
- **WHEN** an agent on Ana's computer makes the table `reading_list` and adds a row
- **THEN** a later command from any of Ana's computers reads the row back

#### Scenario: An agent reaches for a synced table
- **WHEN** an agent sends a command that reads or changes `relay_notes`
- **THEN** it fails because no such table is there, and Ana's notes are unchanged

#### Scenario: A phone key tries
- **WHEN** a phone key or an API key sends a command to the agents' database
- **THEN** it is refused

### Requirement: The agents' database has limits and stays private
The agents' database SHALL refuse a command, an answer or a database beyond its published size limits, with the limit in the reason. Relay Everything SHALL NOT send its contents to a webhook, the AI connector or an export, and SHALL put no health or location data into it.

#### Scenario: The database is full
- **WHEN** an agent writes past the database's size limit
- **THEN** the write is refused with the limit, and the rows already there stay
