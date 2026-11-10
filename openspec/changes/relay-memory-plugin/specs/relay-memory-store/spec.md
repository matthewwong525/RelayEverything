## ADDED Requirements

### Requirement: The person's space answers memory's store requests
Relay Everything SHALL answer each of WongStack memory's twelve store operations from the person's own space, so memory saves, searches and summarises facts there with no second memory. Each operation SHALL be answered only for a computer key, and only from its own person's space. No operation SHALL take a database command, a table name or an owner from the caller. The store SHALL pass memory's own store check.

#### Scenario: A chat saves a fact
- **WHEN** memory on Ana's connected computer saves "the battery is 40 mAh" with the topic `battery`
- **THEN** the fact is in Ana's memory table, and a search for `battery` from that computer finds it

#### Scenario: Another key asks
- **WHEN** an API key, the AI connector or a phone key calls a memory store operation
- **THEN** it is refused, and nothing in the space is read or changed

### Requirement: The store keeps facts add-only
No store operation SHALL change a fact's words or delete a fact. A fact that replaces another SHALL mark the old one replaced in the same step, and the old fact SHALL stay readable. Adding topics to a fact SHALL keep its words, time and device. Closing a thread SHALL add a new fact that replaces it.

#### Scenario: A decision changes
- **WHEN** memory saves "the battery is 50 mAh" replacing the 40 mAh fact
- **THEN** a live search shows 50 mAh, and a search with replaced facts shows 40 mAh, marked replaced

### Requirement: Facts use memory's five kinds
A new fact SHALL be one of `user`, `feedback`, `project`, `reference` or `thread`, and any other kind SHALL be refused. A fact saved before with an older kind SHALL keep its stored words and SHALL read through the store as its nearest kind: `open` as `thread`, `preference` as `feedback`, `fact`, `decision` and `plan` as `project`.

#### Scenario: An old open fact
- **WHEN** memory asks for open threads, and the space holds an older fact of kind `open`
- **THEN** that fact is among the threads, and its stored row is unchanged

### Requirement: A fact links to where it came from
Every fact the store adds SHALL have at least one `relay:` source: the saved chat of the session it came from, or, with no saved chat, the day it was saved. A source that names a record not in the space SHALL be refused. A fact's transcript SHALL be its saved chat, and the store SHALL keep no second copy of a chat.

#### Scenario: A fact from a saved chat
- **WHEN** memory saves a fact from a session whose chat Relay Everything saved
- **THEN** the fact's source is that chat, and asking for its transcript gives the chat's messages

#### Scenario: Saving is off
- **WHEN** saving is off in the project
- **THEN** memory has no store there, and no fact or chat from that project reaches the space
