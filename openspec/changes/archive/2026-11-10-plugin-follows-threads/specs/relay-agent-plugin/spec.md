## MODIFIED Requirements

### Requirement: The AI reads and adds through skills
On a connected computer, the AI SHALL be able to read the person's notes, health, sleep, workouts, places, the location points of a stay or trip, calendar and saved chats, and add a note, through the plugin's skills, with the computer's own key, from that person's space only. Each answer SHALL be bounded as the web API bounds it. A computer with an old chat-only key, or none, SHALL be told to run `/relay:connect`.

#### Scenario: Ask about a day
- **WHEN** the person asks the AI what they noted yesterday
- **THEN** the AI answers from that person's notes for yesterday, through the plugin, with no connector

#### Scenario: An old chat-only key
- **WHEN** the AI tries to read on a computer whose key only sends chats
- **THEN** it reads nothing and tells the person to run `/relay:connect`

#### Scenario: Ask about a trip's route
- **WHEN** the person asks which way they walked on a trip that the places read lists
- **THEN** the AI reads that trip's location points through the plugin and answers from them

### Requirement: Saving can be turned off per project
Saving SHALL be on in every project until the person turns it off there. With saving off, nothing from that project SHALL be sent, and the save skill SHALL say how to turn it on. The person SHALL be able to see whether saving is on and when the project last sent. A git worktree SHALL count as its main repository: a chat in any worktree SHALL carry the main repository's name, and saving off or on SHALL hold in every worktree of it, made before or after.

#### Scenario: Saving is off
- **WHEN** the person turns saving off in a project and then chats there
- **THEN** nothing from that project reaches Relay Everything

#### Scenario: A new workspace copy
- **WHEN** the person turned saving off in a repository, and later starts a chat in a new worktree of it
- **THEN** nothing from that chat reaches Relay Everything

#### Scenario: A chat in a workspace copy is named
- **WHEN** a chat runs in a worktree named `rural-horse` of the `WongOS` repository, with saving on
- **THEN** Relay Everything shows the chat under the project `WongOS`

## ADDED Requirements

### Requirement: The AI sees the person's topics when a chat starts
When a chat starts on a connected computer, the plugin SHALL give the AI the person's top-level topics, one short line each, from the computer's copy of the web, at most 40 lines, and the project's own topic when one has the project's name. The chat SHALL NOT wait for the network: the copy SHALL be synced on its own. With no copy or no topics, the plugin SHALL add nothing.

#### Scenario: A chat starts
- **WHEN** a chat starts and the copy holds the topics `battery`, `ring` and `ring/charging`
- **THEN** the AI gets `battery` and `ring` with their summaries, and not `ring/charging`

#### Scenario: An empty web
- **WHEN** a chat starts and the copy holds no topics
- **THEN** the plugin adds nothing to the chat

### Requirement: A message brings in the topics it names
Before the AI reads each message, the plugin SHALL look for the person's topic names in it, in the computer's copy, with no network call. A clear match SHALL add the topic's summary, a weak match SHALL add only its name, and no more than 3 topics SHALL be added. A message that names no topic SHALL get nothing added.

#### Scenario: A clear match
- **WHEN** the person asks "is the battery still 40 mAh?" and `battery` is a topic
- **THEN** the AI gets the `battery` topic's summary with the message

#### Scenario: No match
- **WHEN** the person's message names no topic
- **THEN** nothing is added to it

### Requirement: The AI pulls a topic in one step
The plugin SHALL give the AI one read that, for a topic, answers together: its page, the topics it links and those that link it, its newest live facts, the notes with its tag, and the titles and summaries of up to 3 chats its facts came from. It SHALL go one step out and no further. A part that fails SHALL NOT hide the parts that were read.

#### Scenario: Pulling a topic
- **WHEN** the AI pulls the topic `battery`
- **THEN** it gets the page, `ring` as a linked topic, the newest facts and notes tagged `battery`, and the chat a fact came from, in one answer

### Requirement: The AI reads all around a moment in one step
The plugin SHALL give the AI one read that, for a note or a time, answers together: the note when one is given, the summary of that moment's day, and the notes, places, calendar events and health by the hour from a window before to the same window after it. The window SHALL be 2 hours each way unless the AI asks for another, and SHALL be at most 12 hours each way. Times SHALL be in the computer's time zone unless the AI names another. A part that fails SHALL NOT hide the parts that were read.

#### Scenario: Around a note
- **WHEN** the AI reads around a note written at 14:20
- **THEN** it gets that note, its day's summary, and the notes, places, events and hourly health from 12:20 to 16:20, in one answer

#### Scenario: A window that is too wide
- **WHEN** the AI asks for a window of 20 hours
- **THEN** the plugin refuses and says the window is at most 12 hours

#### Scenario: One part can not be read
- **WHEN** the calendar part of the read fails but the others succeed
- **THEN** the answer holds the other parts and says that the calendar could not be read

### Requirement: The AI follows connected threads
The `ask` skill SHALL tell the AI to start from the person's topics and facts, and to read raw data only to dig in; and, for each kind of starting point, which reads lead on from it: from a topic, to its facts and their sources; from a note, to all around it and to saved chats on its subject; from a day, to its nights, workouts, places and events; from a stay or trip, to its points; from a saved chat, to the notes and days it names. The AI SHALL follow a thread only while it helps to answer the question, and SHALL say where each fact came from.

#### Scenario: A question about a note's context
- **WHEN** the person asks what was going on when they wrote a note
- **THEN** the AI reads all around that note and searches saved chats with the note's key words, and its answer names the day, the place, the event and any related chat it found
