# relay-memory-store Specification

## Purpose
TBD - created by archiving change relay-memory-plugin. Update Purpose after archive.

## Requirements

### Requirement: The person's space answers memory's store requests
Relay Everything SHALL answer each of WongStack memory's twelve store requests from the person's own space, so memory saves, searches and summarises facts there with no second memory. This SHALL serve the plugin's copy of memory and a full WongStack project whose memory connects to the space. Each request SHALL be answered only for a computer key, and only from its own person's space. No request SHALL take a database command, a table name or an owner from the caller. The store SHALL pass memory's own store check.

#### Scenario: A chat saves a fact
- **WHEN** memory on Ana's connected computer saves "the battery is 40 mAh" with the topic `battery`
- **THEN** the fact is in Ana's memory table, and a search for `battery` from that computer finds it

#### Scenario: A WongStack project on the store
- **WHEN** WongOS's memory, set to Matthew's space with his computer's key, starts a chat and saves a fact
- **THEN** the chat start shows Matthew's facts from his space, and the new fact is in his memory table

#### Scenario: Another key asks
- **WHEN** an API key, the AI connector or a phone key calls a memory store request
- **THEN** it is refused, and nothing in the space is read or changed

### Requirement: The store keeps facts add-only
No store request SHALL change a fact's words or delete a fact. A fact that replaces another SHALL mark the old one replaced in the same step, and the old fact SHALL stay readable. Adding topics to a fact SHALL keep its words, time and author. Closing a thread SHALL add a new fact that replaces it.

#### Scenario: A decision changes
- **WHEN** memory saves "the battery is 50 mAh" replacing the 40 mAh fact
- **THEN** a live search shows 50 mAh, and a search with replaced facts shows 40 mAh, marked replaced

### Requirement: Facts use memory's five kinds
A new fact SHALL be one of `user`, `feedback`, `project`, `reference` or `thread`, and any other kind SHALL be refused. A fact saved before with an older kind SHALL keep its stored words and SHALL read through the store as its nearest kind: `open` as `thread`, `preference` as `feedback`, `fact`, `decision` and `plan` as `project`.

#### Scenario: An old open fact
- **WHEN** memory asks for open threads, and the space holds an older fact of kind `open`
- **THEN** that fact is among the threads, and its stored row is unchanged

### Requirement: A fact links to where it came from
The store SHALL give back each fact's sources exactly as memory wrote them. Every fact the store adds SHALL also have a `relay:` source for Relay Everything's pages: the saved chat of the session it came from, or, with no saved chat, the day it was saved. A `relay:` source that names a record not in the space SHALL be refused.

#### Scenario: A fact from a saved chat
- **WHEN** memory saves a fact with the source `session:claude:1234` from a session whose chat Relay Everything saved
- **THEN** memory reads back `session:claude:1234`, and the person's page shows the saved chat as the fact's source

#### Scenario: Saving is off
- **WHEN** saving is off in the project
- **THEN** the plugin's memory has no store there, and no fact or chat from that project reaches the space

### Requirement: A fact's transcript can be read
The store SHALL keep each chat transcript memory sends, in the person's own space, and SHALL give it for any fact from that chat. With no kept transcript, it SHALL give the saved chat, and with neither, it SHALL say why. Deleting the account SHALL delete the transcripts.

#### Scenario: Reading where a fact came from
- **WHEN** memory asks for the transcript behind a fact whose chat sent its transcript
- **THEN** it gets that transcript

#### Scenario: No transcript was sent
- **WHEN** memory asks for the transcript behind a fact from a chat that sent none and that Relay Everything did not save
- **THEN** it gets a short answer that says the transcript is missing, and nothing fails

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
