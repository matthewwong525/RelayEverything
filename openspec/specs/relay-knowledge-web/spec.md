# relay-knowledge-web Specification

## Purpose
Each person's memory table of facts, kept in their space with columns they can change, and their knowledge web of topic pages that sum the facts up, under rules the person can change, kept as a git repository in Relay Everything, written in an open format, and reached by a connected computer's key.

## Requirements

### Requirement: Each person has one knowledge web
Relay Everything SHALL keep for each person one knowledge web of pages, a git repository that only that person's callers can reach. It SHALL make the web the first time one of the person's computers asks for it, holding a start page and the default rules page. Every change SHALL be kept in the repository's history.

#### Scenario: The first ask makes the web
- **WHEN** a computer of Ana's asks for her web, and she has none
- **THEN** Relay Everything makes it with `README.md` and `FORMAT.md`, and the computer can read both

#### Scenario: Ana can't reach Ben's web
- **WHEN** Ana's computer uses its pass on Ben's web
- **THEN** it is refused

### Requirement: A connected computer gets a short pass
Any plugin that holds a computer key SHALL be able to open the web the same way. A computer key SHALL be able to ask for a pass that reads and writes its own person's web, for at most one hour. A phone key, a turned-off key, a person's page session and an API key SHALL be refused. The answer SHALL give the web's git address, the pass, and when the pass ends.

#### Scenario: A computer asks for a pass
- **WHEN** a connected computer asks for a pass
- **THEN** it gets its person's web address and a pass that ends within one hour

#### Scenario: A phone asks
- **WHEN** a phone key asks for a pass
- **THEN** it is refused and gets no pass

#### Scenario: A computer is turned off
- **WHEN** the person turns a computer off, and that computer then asks for a pass
- **THEN** it is refused

### Requirement: The computer keeps a copy and sends changes
The plugin SHALL keep a copy of the person's web in its own folder on the computer. It SHALL be able to fetch the newest pages and to send this computer's changes, and SHALL join changes made on two computers without losing either. A pass SHALL never be written into the copy, a log or a chat. A computer SHALL sync at most once every 15 minutes, unless it has changes of its own to send or the person asks for a sync; between syncs it SHALL read its own copy.

#### Scenario: A second sync too soon
- **WHEN** a computer synced 5 minutes ago, has no changes of its own, and a new chat starts
- **THEN** it does not reach Relay Everything, and reads its own copy

#### Scenario: Two computers write
- **WHEN** a laptop and a desktop each change a different page and each send
- **THEN** the web holds both changes, and each computer gets both at its next fetch

### Requirement: The person's web holds its own rules
Each web SHALL hold `FORMAT.md`, which says the kinds of fact, which the server SHALL take as any text in the `kind` column, how a fact and a topic page are written, and how links are written. A new web's `FORMAT.md` SHALL be the default, and the same default SHALL be on the public website. The person SHALL be able to change their web's `FORMAT.md`, and a plugin SHALL read the web's own `FORMAT.md` before it writes, and follow it over its own default.

#### Scenario: Ana adds a kind of fact
- **WHEN** Ana adds the kind `idea` to her web's `FORMAT.md`, and her plugin later writes facts from a chat full of ideas
- **THEN** those facts carry the kind `idea`, and the server takes them

### Requirement: Each person has one memory table of facts
Relay Everything SHALL keep for each person one memory table in their own space, and each row SHALL be a fact. Every fact SHALL have an id, at least one subject tag, at least one source link, the facts it replaces, the device that added it and the time, which Relay Everything sets and checks. Every other column SHALL be the person's, and a new memory table SHALL have the columns `kind` and `text`, both required. A fact SHALL only be added: no route SHALL change or delete its columns, sources or replaces, or delete it, except deleting the account. A computer key MAY add and remove a fact's tags, and a fact SHALL keep at least one. A new fact MAY name the facts it replaces; a replaced fact SHALL stay readable and SHALL be marked replaced. A fact with no tag, no source link or a required column missing SHALL be refused.

#### Scenario: A decision changes
- **WHEN** a computer adds a fact that the battery is now 50 mAh, naming the fact that said 40 mAh as replaced
- **THEN** a search for live facts on `#battery` shows 50 mAh, and the 40 mAh fact is still readable, marked replaced

#### Scenario: A fact with no source
- **WHEN** a computer adds a fact with no source link
- **THEN** it is refused, and nothing is stored

### Requirement: Plugins change the memory table's columns and reach no other table
A computer key SHALL be able to read the memory table's columns, and to add a column, change a column's note or whether it is required, and remove a column. A column's type SHALL NOT change, and a removed column's values SHALL stay in the old facts that hold them. Each fact's values SHALL be checked against the columns when it is added. Relay Everything SHALL keep each column change with its time and device. No caller SHALL make another table, send a database command, or change the columns Relay Everything keeps. An API key and the AI connector SHALL be able to read the columns and SHALL NOT change them. A phone key SHALL NOT reach `/v1/`.

#### Scenario: A plugin adds a column
- **WHEN** a mood plugin on Ana's computer adds the column `mood`, a short text, and then adds a fact with a mood
- **THEN** the fact is stored with its mood, Ana's other plugins see the new column, and her older facts read as before

#### Scenario: A plugin tries another table
- **WHEN** a plugin asks to make its own table, or sends a database command
- **THEN** it is refused, and nothing in the person's space changes

#### Scenario: A value of the wrong type
- **WHEN** a computer adds a fact with a word in a number column
- **THEN** it is refused, and nothing is stored

### Requirement: The memory table can be searched and added to by connected callers
A computer key SHALL be able to add facts and read them. A computer key, an API key and the AI connector SHALL be able to search facts by words, tag, source, time and the value of any of the person's columns, live facts only unless all are asked for, and to read one fact with the facts it replaced and the fact that replaced it. A phone key SHALL be refused. Each answer SHALL be bounded, with a cursor to read on.

#### Scenario: The phone's AI asks
- **WHEN** the Claude app, through the AI connector, searches the memory for `battery`
- **THEN** it gets the live facts that hold that word, newest first, each with its columns, tags and sources

#### Scenario: A phone key asks
- **WHEN** a phone key searches the memory
- **THEN** it is refused

### Requirement: Topic pages sum up facts
A topic page SHALL sum up the live facts that carry its tag, and SHALL NOT list their ids. A topic page's name SHALL be its tag, so that its facts and notes are found by a search for that tag. Each page SHALL have a one-line summary, and `README.md` SHALL list the top-level topics with their summaries. The default `FORMAT.md` SHALL say this way to look: read the list of topics, read a page, search the memory and the notes by its tag, then open a source.

#### Scenario: A page and its facts
- **WHEN** an AI reads `topics/battery.md`, which says the battery stays 40 mAh, and wants to know why
- **THEN** a memory search for `#battery` finds the fact, and that fact links its chat

### Requirement: Notes have topics that the person's own AI gives them
A note SHALL be able to carry topic tags in the same form as a fact's. Only a computer key SHALL add or remove a note's tags, and a tag change SHALL NOT change the note's words. Each tag change on a note or a fact SHALL be kept with its device and time. A computer key, an API key and the AI connector SHALL be able to find notes by tag. No model SHALL run on the server to give tags; the person's own AI on their computer gives them.

#### Scenario: The helper files a note
- **WHEN** a computer adds the tag `ring/charging` to a note about the charger cable
- **THEN** a search for notes tagged `ring/charging` finds it, and its words are as the person wrote them

#### Scenario: A phone key tags a note
- **WHEN** a phone key asks to add a tag to a note
- **THEN** it is refused, and the note's tags stay as they were

### Requirement: Facts and pages link to their sources
A fact or a page SHALL link to the record it came from as `relay:<kind>/<id>`, where the kind is note, chat, day, night, workout, stay, event or photo, and a chat link MAY name a message as `#<number>`. A fact or a page SHALL NOT copy a health value or a location point; it SHALL link to its day, night, workout or stay instead.

#### Scenario: A link opens its source
- **WHEN** a fact links `relay:chat/7f3a#120`
- **THEN** an AI can read that chat at message 120 through the web API with the computer's key

### Requirement: Topics grow from use
The default rules SHALL have one kind of page in the web, a topic, with no set folders for people, projects or places. A topic page SHALL be made when the first fact tags it, and SHALL NOT be made before. A topic that grows big MAY become a folder with its own start page. A chat SHALL NOT get a page in the web; its facts SHALL link to it.

#### Scenario: The first fact about Sam
- **WHEN** the first fact tagged `#sam` is added, and the plugin next writes pages
- **THEN** `topics/sam.md` is made and sums up that fact, and no other folder is made

### Requirement: Links are written one way
A fact SHALL link to its sources, and a page MAY link to other pages and to records. No link SHALL be written a second time in the other direction, and no page SHALL list fact ids; a page's facts SHALL be found by its tag, and a record's facts by a memory search for its link.

#### Scenario: What came from a chat
- **WHEN** an AI wants every fact and page about chat `7f3a`
- **THEN** a memory search for the source `relay:chat/7f3a` finds its facts, and their tags name the pages, with no list kept on the chat

### Requirement: A server without Artifacts says so
A Relay Everything server whose Cloudflare account has no Artifacts SHALL answer a pass request with a clear refusal that says the knowledge web is not set up on that server, and every other route, the memory table too, SHALL work as before.

#### Scenario: A self-hosted server on the free plan
- **WHEN** a computer connected to such a server asks for a pass
- **THEN** it gets the refusal, and the plugin tells the person the web is not set up there
