## ADDED Requirements

### Requirement: The person's own AI builds the web once a day
On a connected computer, the first chat start of the person's local day SHALL start a build of their memory and knowledge web in the background, run by the AI app that chat started in, on that computer. The chat SHALL NOT wait for the build. No model SHALL run on the server for it, and the person SHALL NOT be asked to pick a topic or tag a note. The build's own chat SHALL NOT be saved and SHALL NOT start another build.

#### Scenario: The first chat of the day
- **WHEN** the person starts their first chat of the day on a connected computer
- **THEN** the chat starts at once with its topics, and a build runs in the background on that computer

#### Scenario: A second chat the same day
- **WHEN** the person starts another chat later that day
- **THEN** no second build starts

### Requirement: Only one computer builds each day
When the person has more than one connected computer, only the first computer to claim the day in the web SHALL build that day. Another computer that finds the day claimed SHALL stop without reading anything.

#### Scenario: Two computers in one morning
- **WHEN** the person starts a chat on their laptop and then on their desktop the same day
- **THEN** only the laptop builds, and the desktop's chat starts no build

### Requirement: Older chats and notes are read into facts
A build SHALL read the saved chats that have been quiet for at least an hour and the notes not yet read, and SHALL add facts in the form the person's `FORMAT.md` gives, each with at least one topic and a link to the message or note it came from. Before it adds a fact, the build SHALL look at the live facts that share its topics or its words, and SHALL add it, add it as a replacement of an older fact, or drop it, so the same fact is not stored twice. A chat that grew since it was read SHALL be read again from where the last read stopped.

#### Scenario: A decision in a chat
- **WHEN** a quiet chat says the bike's battery is now 500 Wh, and a live fact says 400 Wh
- **THEN** the build adds a fact that the battery is 500 Wh, which replaces the 400 Wh fact and links that chat message

#### Scenario: The chat in progress
- **WHEN** a build runs while the person's chat had a message 10 minutes ago
- **THEN** that chat is not read in this build

### Requirement: Notes get topics from the build
A build SHALL give each note it reads the topics that fit it, through the computer's key, and SHALL NOT change the note's words. A note with nothing worth keeping MAY get no topic and no fact.

#### Scenario: A note about the charger
- **WHEN** a build reads the note "Charger cable is too short"
- **THEN** the note gets the topic `bike-charger`, and its words stay the same

### Requirement: The build writes and tidies topic pages
After it reads, a build SHALL write or update a page for each topic whose facts changed, by the person's `FORMAT.md`, and SHALL keep `README.md`'s list of topics and their one-line summaries current. By the default rules, it SHALL keep pages side by side and SHALL split a big topic into smaller pages that link each other, not into a folder. It SHALL join topics that are the same into one, moving their facts' and notes' topics, and SHALL fix broken links. It SHALL send the web's changes back when it ends.

#### Scenario: Two names for one topic
- **WHEN** the web has both `bike-battery` and `bikebattery`
- **THEN** after the build only `bike-battery` has a page, and the facts and notes of `bikebattery` carry `bike-battery`

#### Scenario: A big topic
- **WHEN** the topic `bike` has grown past what one page sums up well
- **THEN** the build makes pages such as `bike-battery` and `bike-charger` beside it, `bike` links them, and no folder is made

### Requirement: Pages link connected ideas across topics
A build SHALL find the topics that share a fact, a note or a chat with each topic it touched, and SHALL add a link from one page to the other where the two are related, with words that say how. It SHALL also link a topic wherever a page names it. A fact or a note that touches two ideas SHALL get both topics. A link SHALL be written on one page only; the other way SHALL be found by a scan of the pages.

#### Scenario: Two topics from one chat
- **WHEN** one chat gave facts tagged `bike-battery` and facts tagged `bike-charger`
- **THEN** after the build one of the two pages links the other with words that say how they connect, and a topic pull of either shows the other

#### Scenario: Topics that share nothing
- **WHEN** two topics share no fact, note or chat, and no page names the other
- **THEN** the build adds no link between them

### Requirement: A new topic looks back
When a build makes a new topic, it SHALL search the person's older facts and notes for ones that fit it, SHALL add the new topic to those it judges to fit, and SHALL link the new page from the pages it connects to.

#### Scenario: A topic made today
- **WHEN** a build makes the topic `garden` from today's notes, and three facts from October are about the garden
- **THEN** those three facts carry `garden` after the build, the `garden` page sums them up, and a page those facts already connect to links `garden`

### Requirement: The past is read a part each day
A build SHALL read the newest unread chats and notes first, at most 20 chats and 100 notes, and SHALL stop after 30 minutes. A record of what was read SHALL be kept in the web, so that every computer of the person reads each chat part and each note once. Each later build SHALL go on from that record until all are read.

#### Scenario: A person with a long past
- **WHEN** a person with 300 saved chats has their first build
- **THEN** it reads their 20 newest chats, and each next day's build reads the next ones

#### Scenario: A stopped build
- **WHEN** a build stops after 30 minutes with 8 of its 20 chats read
- **THEN** the next build does not read those 8 again

### Requirement: The build never reads health or places
The build SHALL NOT be able to read health, places, routes, calendar events or photos. A fact or a page it writes SHALL link to a source's day by time, and SHALL NOT copy a health value or a location point.

#### Scenario: A note about a long ride
- **WHEN** a build reads a note about a long bike ride
- **THEN** the fact links the note and its day, and holds no heart rate, distance or route

### Requirement: The person can see and stop the build
On each computer, the person SHALL be able to see when the last build ran, on which computer, what it read and added, and how much is still to read; turn the daily build off and on again on that computer; and start one at once.

#### Scenario: Turned off
- **WHEN** the person turns the build off on their laptop and starts a chat the next day
- **THEN** the laptop starts no build, and the chat's topics still show
