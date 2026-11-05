# relay-server-address Specification

## Purpose
Say where the private Relay site answers, how its old address keeps devices working through a move, and which address a new device key carries.

## Requirements

### Requirement: The private site answers at app.relayeverything.com

The private Relay site SHALL answer at app.relayeverything.com behind the same login as before. A device key made before the move SHALL keep working there with no change to the key. A device key made after the move SHALL show app.relayeverything.com as its server address.

#### Scenario: An old key reaches the new address
- **WHEN** a phone sends a note to app.relayeverything.com with a device key made before the move
- **THEN** the note is kept, as at the old address

#### Scenario: The address stays private
- **WHEN** a person with no login and no device key opens app.relayeverything.com
- **THEN** the site asks for the login and shows no Relay data

### Requirement: The old address forwards for 30 days

For 30 days after the move, the old relay-ring workers.dev address SHALL pass every request on to the new site with its method, body and key unchanged, and SHALL send a browser that opens a page to the same page at the new address. A request with no valid login or device key SHALL be refused, as at the new address. After the 30 days, the old address SHALL be removed only after the owner says yes.

#### Scenario: The Pebble sends to the old address
- **WHEN** the Pebble webhook posts a signed note to the old address in the 30 days
- **THEN** the new site keeps the note once, as if it was posted there

#### Scenario: A browser opens the old address
- **WHEN** the owner opens a page at the old address
- **THEN** the browser goes to the same page at app.relayeverything.com

### Requirement: The AI connector keeps answering for 30 days

The AI connector SHALL answer at its new relay-everything-mcp address with a new sign-in. For 30 days after the move, an AI app connected at the old relay-ring-mcp address SHALL keep its sign-in and SHALL read the same current data as the new address.

#### Scenario: The Claude app asks after the move
- **WHEN** the Claude app, still connected at the old connector address, asks for a note kept after the move
- **THEN** it gets that note

### Requirement: A sign-in finishes on the site after every publish

A person who signs in at app.relayeverything.com SHALL land on the Relay site, in a browser and through the command-line sign-in. A publish SHALL keep the address that the login returns to turned on. A publish whose settings would turn that address off SHALL stop before it changes the site, and SHALL name the setting to add.

#### Scenario: Sign in after a publish
- **WHEN** the owner signs in at app.relayeverything.com after a publish
- **THEN** the browser shows the Relay site, not a *There is nothing here yet* page, and the command-line sign-in gets its token

#### Scenario: Settings that would turn the address off
- **WHEN** a publish runs with a custom domain in the live settings and no setting that keeps the workers.dev address on
- **THEN** the check before the publish stops it and names `workers_dev`
