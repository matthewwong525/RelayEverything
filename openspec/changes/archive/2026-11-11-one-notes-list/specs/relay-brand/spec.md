## MODIFIED Requirements

### Requirement: Each app screen keeps the brand's screen rules

Each screen of the phone app SHALL follow the four screen rules: one main action in the accent color, cards with no border, a word with every state color, and soft corners. On Home and the notes list, *New note* SHALL be the only control filled with the accent color. A row in the notes list SHALL show no *Voice* or *Typed* tag; a voice note's row SHALL show a small microphone and its length in the accent text color. The picked filter SHALL be ink, not the accent color.

#### Scenario: The notes list has one bright thing

- **WHEN** a person opens the notes list with a typed note and a voice note
- **THEN** *New note* is the only control filled with the accent color, no row has a tag, and nothing on the list uses the spark color while nothing records

## REMOVED Requirements

### Requirement: The sync state says its name, and only syncing moves

**Reason**: The *Sync now* arrows leave the sync line, so the rule about their motion goes; the rest moves to *The sync state shows only when something is wrong*.

**Migration**: The app syncs when it opens and comes back, and a pull down on Home or the notes list syncs now. *Synced*, *Syncing* and *On this phone* no longer show.

## ADDED Requirements

### Requirement: The sync state shows only when something is wrong

Under the title of Home and of the notes list, the phone app SHALL show a sync state only while sending is on and notes wait or can't go: the number waiting, or *Key refused*, in words beside a small dot. Offline with no note waiting, it SHALL show no state; offline with notes waiting, it SHALL show the number waiting. The state SHALL be words, not a button. With every note sent, or with sending off, it SHALL show no state: Home SHALL show no line, and the notes list only its count. The dot SHALL pulse only while the waiting notes send, and SHALL stay still when the phone asks for reduced motion. There SHALL be no *Sync now* button: notes send by themselves, and a pull down on the page syncs now. The logo SHALL not move.

#### Scenario: Waiting notes send, then the state goes

- **WHEN** one note waits and the phone sends it
- **THEN** the state says *1 waiting* with a pulsing dot, and then Home shows no line and the notes list shows only its count

#### Scenario: Offline with every note sent shows no state

- **WHEN** sending is on, no note waits, and the phone can not reach the server
- **THEN** Home shows no line, the notes list shows only its count, and no *Offline* shows

#### Scenario: Reduced motion keeps the dot still

- **WHEN** the phone is set to reduce motion and a waiting note sends
- **THEN** the state says *1 waiting* and its dot does not move
