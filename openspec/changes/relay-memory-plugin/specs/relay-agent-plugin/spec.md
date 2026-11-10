## MODIFIED Requirements

### Requirement: The AI sees the person's topics when a chat starts
In a repo with no memory of its own, when a chat starts on a connected computer, the plugin SHALL give the AI the person's top-level topics, one short line each, from the computer's copy of the web, whether memory is on or off. The chat SHALL NOT wait for the network: the copy SHALL be synced on its own. With no copy or no topics, nothing SHALL be added. In a repo with its own memory, the plugin SHALL add no topics: the repo's memory gives its own.

#### Scenario: A chat starts
- **WHEN** a chat starts and the copy holds the topics `battery`, `ring` and `ring/charging`
- **THEN** the AI gets `battery` and `ring` with their summaries, and not `ring/charging`

#### Scenario: An empty web
- **WHEN** a chat starts and the copy holds no topics
- **THEN** nothing is added to the chat

#### Scenario: A repo with its own memory
- **WHEN** a chat starts in WongOS, which has its own memory, with the Relay Everything plugin on
- **THEN** the AI gets WongOS's memory summary and no Relay Everything topics, and the plugin still reads notes, health and places

### Requirement: A message brings in the topics it names
In a repo with no memory of its own, before the AI reads each message, the plugin SHALL look for the person's topic names in it, with no network call. A clear match SHALL add the topic's summary, a weak match SHALL add only its name, and no more than 3 topics SHALL be added. A message that names no topic SHALL get nothing added, and a topic SHALL be added once, even with memory on.

#### Scenario: A clear match
- **WHEN** the person asks "is the battery still 40 mAh?" and `battery` is a topic
- **THEN** the AI gets the `battery` topic's summary with the message, once

#### Scenario: No match
- **WHEN** the person's message names no topic
- **THEN** nothing is added to it

### Requirement: The AI pulls a topic in one step
The plugin SHALL give the AI one read that, for a topic, answers together: its page, the topics it links and those that link it, its newest live facts, the notes with its tag, and the titles and summaries of up to 3 chats its facts came from. It SHALL go one step out and no further. A part that fails SHALL NOT hide the parts that were read.

#### Scenario: Pulling a topic
- **WHEN** the AI pulls the topic `battery`
- **THEN** it gets the page, `ring` as a linked topic, the newest facts and notes tagged `battery`, and the chat a fact came from, in one answer

## ADDED Requirements

### Requirement: Setup asks whether to turn memory on
When a computer connects, the plugin SHALL ask whether to also remember things for the person, and SHALL keep the answer on that computer. Memory SHALL be off until the person says yes, and a computer connected before memory came SHALL read as off. The person SHALL be able to turn memory on or off later. With memory off, the plugin SHALL work as before: notes, health, places, around a moment and chat saving.

#### Scenario: The person says no
- **WHEN** Ana connects her computer and answers no
- **THEN** her chats are saved and the AI reads her notes, and no fact is saved by memory

#### Scenario: An older connection
- **WHEN** a computer connected before this release starts a chat
- **THEN** memory is off, and nothing about it changes until Ana turns it on

### Requirement: With memory on, the plugin runs the person's WongStack memory
With memory on, in a repo with no memory of its own, the plugin SHALL run WongStack's memory from a copy inside the plugin, with nothing else to install, in Claude Code and in Codex: its save check, its summary at chat start, its search and its before-edit warnings, with the facts kept in the person's space. The copy SHALL match the WongStack memory in this repository at each plugin release. In a repo with its own memory, the plugin's memory SHALL stay off, so memory never runs twice in a chat.

#### Scenario: Memory in a side project
- **WHEN** Ana turns memory on and the AI in her side project saves "the battery is 40 mAh"
- **THEN** the fact is in her Relay Everything space, and the next chat's summary shows it

#### Scenario: Memory in WongOS
- **WHEN** Ana has memory on and starts a chat in WongOS, which has its own memory
- **THEN** only WongOS's memory runs, and no fact goes to her space from that chat

### Requirement: Relay Everything's plugin owns notes, health, places and around a moment
Notes, health, places, calendar, saved chats and *around a moment* SHALL be read and added only through the plugin's own commands, in any repo, with memory on or off. Memory SHALL NOT read them, and a fact SHALL point to them only by a `relay:` source link.

#### Scenario: Around a moment in a repo with its own memory
- **WHEN** the person asks in WongOS what they were doing when they wrote the battery note
- **THEN** the plugin answers with the note, its day, and the places and health around it, and WongOS's memory is not asked for them
