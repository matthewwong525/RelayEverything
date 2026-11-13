# Spec Delta

## MODIFIED Requirements

### Requirement: A WongStack memory moves in once
Relay Everything SHALL import a WongStack project's memory into a memory not yet used, keeping each fact's number, date, author, owner, kind, topics, sources and replaced-by link, each chat's session record, the topic definitions and the transcripts. The import SHALL read the source only, and SHALL change nothing there. Each read SHALL ask the source for at most 90 fact numbers, so a source store that takes at most 100 in one request gives every fact. Its first run SHALL be refused once memory has used the space. A later run, or a run after a stop, SHALL add only the facts not yet imported, with their replaced-by links, and no fact SHALL be stored twice.

#### Scenario: WongOS moves in
- **WHEN** Matthew imports WongOS's memory into his space
- **THEN** fact #628 is #628 in his space, with its date, author and topics, a replaced fact still shows its replacement, and the transcript behind an imported fact reads back

#### Scenario: A source store that takes at most 100 numbers a request
- **WHEN** the source store refuses a request for more than 100 fact numbers, and it holds 450 facts
- **THEN** the import reads all 450, and none of its requests is refused

#### Scenario: Memory already used the space
- **WHEN** an import starts in a space where memory has saved facts
- **THEN** it is refused, and nothing in the space changes

#### Scenario: A second run after the switch
- **WHEN** WongOS saved two facts in its old store after the first run, switched to the space, and runs the import again
- **THEN** only those two facts are added, each linked to any fact it replaces, and the old store is only read
