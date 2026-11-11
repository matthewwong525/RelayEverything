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

### Requirement: Each app screen keeps the brand's screen rules

Each screen of the phone app SHALL follow the four screen rules: one main action in the accent color, cards with no border, a word with every state color, and soft corners. On Home and the notes list, *New note* SHALL be the only control filled with the accent color. A row in the notes list SHALL show no *Voice* or *Typed* tag; a voice note's row SHALL show a small microphone and its length in the accent text color. The picked filter SHALL be ink, not the accent color.

#### Scenario: The notes list has one bright thing

- **WHEN** a person opens the notes list with a typed note and a voice note
- **THEN** *New note* is the only control filled with the accent color, no row has a tag, and nothing on the list uses the spark color while nothing records

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
