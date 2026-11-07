## ADDED Requirements

### Requirement: The phone app and its Android share card wear the brand

The phone app and its Android share card SHALL use the Relay Everything brand: one picked color set of paper, card, ink, muted, a bright main color and a spark color, in a light version and a dark version that follow the phone's setting, and the Inter font. The font SHALL be part of the app, so the app shows it with no network call.

#### Scenario: Light and dark follow the phone

- **WHEN** a person opens the app with the phone in dark mode
- **THEN** the app shows the brand's dark colors, and with the phone in light mode it shows the brand's light colors

#### Scenario: The font needs no network

- **WHEN** a person opens the app with sending off and no network
- **THEN** the text shows in Inter and the app makes no network call

### Requirement: Every text color is easy to read

Each text color the brand uses SHALL have a contrast of at least 4.5 to 1 against each background it is used on, in light and in dark, including the text on the main button and on the spark color.

#### Scenario: A color change that lowers contrast fails the check

- **WHEN** a change sets a brand color so that muted text on paper falls below 4.5 to 1
- **THEN** the app's tests fail and name the color pair

### Requirement: One logo and one app icon

Relay Everything SHALL have one logo, a mark of wires meeting in one place beside the name, and one app icon made from it: the mark on the brand's main color. The iPhone and Android home screens, the launch screen, and the website's top bar and browser tab SHALL show this mark, and none of them SHALL show the old ring circle.

#### Scenario: The new icon on the home screen

- **WHEN** a person installs the next build on an iPhone or an Android phone
- **THEN** the home screen shows the icon in the brand's main color with the new mark

#### Scenario: The website shows the new mark

- **WHEN** a person opens relayeverything.com
- **THEN** the top bar and the browser tab show the new mark, and no page outside the ring's own pages shows the ring circle as the product's logo

### Requirement: The website wears the brand

The public website SHALL use the brand's main color as its accent and Inter as its font, in light and dark, with the font served from the website itself.

#### Scenario: The site loads no outside font

- **WHEN** a person opens any page of relayeverything.com
- **THEN** the page shows Inter and loads no file from another address for it
