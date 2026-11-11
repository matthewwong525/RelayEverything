## ADDED Requirements

### Requirement: The AI uses the agents' database through a skill
The plugin SHALL give the AI one command that sends database commands to the person's agents' database and one that lists its tables, with the computer's own key. The skill SHALL tell the AI not to copy health or place data into it.

#### Scenario: Listing tables
- **WHEN** the AI asks for the agents' database's tables
- **THEN** it gets each table with its columns and row count
