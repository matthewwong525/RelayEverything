# relay-brand Specification

## Purpose
Relay Everything has one look: the Signal R logo, the Emerald colors and the Inter font. The phone app, its Android share card, its icon and launch screen, and the website use it, and every text color stays easy to read in light and dark.

## Requirements

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

### Requirement: Every text color is easy to read

Each text color the brand uses SHALL have a contrast of at least 4.5 to 1 against each background it is used on, in light and in dark, including the text on the main button and on the spark color.

#### Scenario: A color change that lowers contrast fails the check

- **WHEN** a change sets a brand color so that muted text on paper falls below 4.5 to 1
- **THEN** the app's tests fail and name the color pair

### Requirement: One logo and one app icon

Relay Everything SHALL have one logo, a capital R that sends out signal waves, beside the name, and one app icon made from it: the mark on the brand's main color. The iPhone and Android home screens, the launch screen, and the website's top bar and browser tab SHALL show this mark, and none of them SHALL show the old ring circle.

#### Scenario: The new icon on the home screen

- **WHEN** a person installs the next build on an iPhone or an Android phone
- **THEN** the home screen shows the icon in the brand's main color with the new mark

#### Scenario: The website shows the new mark

- **WHEN** a person opens relayeverything.com
- **THEN** the top bar and the browser tab show the new mark, and no page shows the ring circle

### Requirement: The website wears the brand

The public website SHALL use the brand's main color as its accent and Inter as its font, in light and dark, with the font served from the website itself.

#### Scenario: The site loads no outside font

- **WHEN** a person opens any page of relayeverything.com
- **THEN** the page shows Inter and loads no file from another address for it

### Requirement: The iPhone share sheet wears the brand

The iPhone share sheet SHALL use the same brand colors as the app, in light and dark following the phone's setting, and the Inter font. The font SHALL be part of the share sheet, so it shows with no network call.

#### Scenario: Sharing on an iPhone in dark mode

- **WHEN** a person with the phone in dark mode and no network shares a web page into Relay Everything
- **THEN** the share sheet shows the brand's dark colors, a green *Save* and text in Inter, and makes no network call for the font

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

### Requirement: Each app screen keeps the brand's screen rules

Each screen of the phone app SHALL follow the four screen rules: one main action in the accent color, cards with no border, a word with every state color, and soft corners. On Home and a notes list, *New note* SHALL be the only control filled with the accent color.

#### Scenario: The notes list has one bright thing

- **WHEN** a person opens the app with a typed note and a voice note
- **THEN** *New note* is the only control filled with the accent color, and the voice note's tag is the only spark on the screen
