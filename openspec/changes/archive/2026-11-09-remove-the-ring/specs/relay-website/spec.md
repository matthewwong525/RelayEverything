## MODIFIED Requirements

### Requirement: The home page introduces Relay

The home page SHALL present Relay as a way to get a person's own data (notes, health, location) off their phone and devices into a place they choose, where their own AI can read it. It SHALL name no ring, and it SHALL link to the Android app, the iPhone TestFlight invite, the app's public code, and the docs.

#### Scenario: A reader wants the app
- **WHEN** a reader opens the home page
- **THEN** they find a link to the Android app, one to TestFlight, and one to the docs

#### Scenario: A reader learns what Relay is
- **WHEN** a reader opens the home page
- **THEN** the headline speaks of their own data in a place they choose, and no part of the page names a ring

### Requirement: The docs cover all of Relay Everything

The docs SHALL hold a menu and a search box, with pages for getting started (what you need, install the app, connect a phone), using the app (notes, health, location, settings), the server API, connections, and privacy. A connection that is not built yet SHALL be shown as coming, with no steps that don't work. The docs SHALL have no ring section, and no page SHALL tell a reader to send notes from the Pebble app to a Relay Everything server.

#### Scenario: A reader looks for the Pebble webhook
- **WHEN** a reader searches the docs for the Pebble webhook
- **THEN** no page gives steps to set it up, and no page names a ring

#### Scenario: A connection is not built yet
- **WHEN** sending to your own database, the AI assistant connection, or the example skill and tables has not been published
- **THEN** its entry says it is coming, and no page gives set-up steps for it

### Requirement: The docs show how to run your own server

The docs SHALL hold a page that gives the request to paste to install Relay in your own account, what it costs, what the install holds, and how to update it. The getting-started pages SHALL point to it. The docs SHALL say that a device key only adds data, and that you read your data on your Relay page or through your AI connector.

#### Scenario: A reader wants their own server
- **WHEN** a reader opens *What you need*
- **THEN** it links to the self-host page, which gives the request to paste and what the install makes

#### Scenario: A reader looks for ring notes on the phone
- **WHEN** a reader opens the notes page
- **THEN** it says the notes from all their devices sync to the phone, and an older recorded note shows as a plain note whose recording opens on tap

## ADDED Requirements

### Requirement: No text people read names the ring

No text a person reads SHALL name the Relay Everything ring: the website, the phone app's screens and permission prompts, the web page, the AI connector's instructions and descriptions, the plugin, and every README. Notes the ring sent SHALL stay in their person's space with their words, place and recording, and SHALL be named *older recorded notes* where a page must name them. The `ring` value of a note's `source` in the API and webhooks SHALL stay, so a program that reads it keeps working. An address under the old `/ring/` docs SHALL open the home page. A change that adds the word *ring* to text people read SHALL fail the project's checks.

#### Scenario: A reader opens an old ring page
- **WHEN** a reader opens relayeverything.com/ring/board/ from a saved link
- **THEN** the home page opens, and no menu entry or page names a ring

#### Scenario: A change brings ring text back
- **WHEN** a change adds *The Relay Everything ring* to a docs page or a phone screen
- **THEN** the checks fail and name the file and line

#### Scenario: An older ring note is read
- **WHEN** a webhook or the API reads a note the ring sent
- **THEN** it gets the note's words, place and recording, with `source` `ring`, as before
