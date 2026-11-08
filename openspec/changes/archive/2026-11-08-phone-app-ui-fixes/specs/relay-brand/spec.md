## MODIFIED Requirements

### Requirement: The phone app and its Android share card wear the brand

The phone app and its Android share card SHALL use the Relay Everything brand: one picked color set of paper, card, ink, muted, a bright main color and a spark color, in a light version and a dark version, and the Inter font. The share card SHALL follow the phone's setting. The app SHALL follow the person's *Appearance* pick: *System*, the default, follows the phone's setting; *Light* and *Dark* keep that version whatever the phone says. The phone SHALL remember the pick. The font SHALL be part of the app, so the app shows it with no network call.

#### Scenario: Light and dark follow the phone

- **WHEN** a person opens the app with the phone in dark mode
- **THEN** the app shows the brand's dark colors, and with the phone in light mode it shows the brand's light colors

#### Scenario: The font needs no network

- **WHEN** a person opens the app with sending off and no network
- **THEN** the text shows in Inter and the app makes no network call

#### Scenario: Light picked on a dark phone

- **WHEN** the phone is in dark mode and the person picks *Light* in Settings, then closes and opens the app
- **THEN** the app shows the brand's light colors at once and after it opens again

### Requirement: The sync state says its name, and only syncing moves

The notes list SHALL name its sync state in words, *Synced*, *Syncing*, the number waiting, *Offline*, *Key refused*, or *On this phone* with sending off, beside a small dot while sending is on. The dot SHALL pulse, and the *Sync now* arrows beside it SHALL turn, only while the state is *Syncing*, and both SHALL stay still when the phone asks for reduced motion. The *Sync now* button SHALL be muted, not filled with the accent color. The logo SHALL not move.

#### Scenario: Syncing pulses, then stops

- **WHEN** the phone sends notes and then finishes
- **THEN** the state says *Syncing* with a pulsing dot, then *Synced* with a still dot

#### Scenario: Reduced motion keeps the dot still

- **WHEN** the phone is set to reduce motion and the app syncs
- **THEN** the state says *Syncing* and its dot does not move

#### Scenario: Reduced motion keeps the arrows still

- **WHEN** the phone is set to reduce motion and the person taps *Sync now*
- **THEN** the state says *Syncing* and the arrows do not turn

## REMOVED Requirements

### Requirement: Each app screen follows the brand's screen rules

**Reason**: Its Settings groups (*Notes*, *Voice notes*, *Sending*) went stale when Sending moved to Home; Settings' groups now live in `relay-home-screen`.
**Migration**: See *Each app screen keeps the brand's screen rules* below, the same rules without the Settings groups.

## ADDED Requirements

### Requirement: Each app screen keeps the brand's screen rules

Each screen of the phone app SHALL follow the four screen rules: one main action in the accent color, cards with no border, a word with every state color, and soft corners. On Home and a notes list, *New note* SHALL be the only control filled with the accent color.

#### Scenario: The notes list has one bright thing

- **WHEN** a person opens the app with a typed note and a voice note
- **THEN** *New note* is the only control filled with the accent color, and the voice note's tag is the only spark on the screen
