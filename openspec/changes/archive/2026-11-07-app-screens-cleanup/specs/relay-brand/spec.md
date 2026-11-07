## ADDED Requirements

### Requirement: The iPhone share sheet wears the brand

The iPhone share sheet SHALL use the same brand colors as the app, in light and dark following the phone's setting, and the Inter font. The font SHALL be part of the share sheet, so it shows with no network call.

#### Scenario: Sharing on an iPhone in dark mode

- **WHEN** a person with the phone in dark mode and no network shares a web page into Relay Everything
- **THEN** the share sheet shows the brand's dark colors, a green *Save* and text in Inter, and makes no network call for the font

### Requirement: Each app screen follows the brand's screen rules

Each screen of the phone app SHALL follow the four screen rules: one main action in the accent color, cards with no border, a word with every state color, and soft corners. On the notes list, *New note* SHALL be the only control filled with the accent color. Settings SHALL show its rows in three groups, *Notes*, *Voice notes* and *Sending*, and every setting SHALL work as before.

#### Scenario: The notes list has one bright thing

- **WHEN** a person opens the app with a typed note and a voice note
- **THEN** *New note* is the only control filled with the accent color, and the voice note's tag is the only spark on the screen

#### Scenario: Settings in three groups, each switch as before

- **WHEN** a person opens Settings with sending off
- **THEN** the rows show under *Notes*, *Voice notes* and *Sending*, *Health*, *Calendar* and *Location history* can not be turned on, and a line says they work with *Send my notes* on

### Requirement: The sync state says its name, and only syncing moves

The notes list SHALL name its sync state in words, *Synced*, *Syncing*, the number waiting, *Offline*, *Key refused*, or *On this phone* with sending off, beside a small dot while sending is on. The dot SHALL pulse only while the state is *Syncing*, and SHALL stay still when the phone asks for reduced motion. The logo SHALL not move.

#### Scenario: Syncing pulses, then stops

- **WHEN** the phone sends notes and then finishes
- **THEN** the state says *Syncing* with a pulsing dot, then *Synced* with a still dot

#### Scenario: Reduced motion keeps the dot still

- **WHEN** the phone is set to reduce motion and the app syncs
- **THEN** the state says *Syncing* and its dot does not move
