# relay-server-address Specification

## Purpose
Say where the private Relay site answers, how its old address keeps devices working through a move, and which address a new device key carries.

## Requirements

### Requirement: The old address forwards for 30 days

For 30 days after the move, the old relay-ring workers.dev address SHALL pass every request on to the new site with its method, body and key unchanged, and SHALL send a browser that opens a page to the same page at the new address. A request with no valid login or device key SHALL be refused, as at the new address. After the 30 days, the old address SHALL be removed only after the owner says yes.

#### Scenario: The Pebble sends to the old address
- **WHEN** the Pebble webhook posts a signed note to the old address in the 30 days
- **THEN** the new site keeps the note once, as if it was posted there

#### Scenario: A browser opens the old address
- **WHEN** the owner opens a page at the old address
- **THEN** the browser goes to the same page at app.relayeverything.com

### Requirement: A sign-in finishes on the site after every publish

A person who signs in at admin.relayeverything.com SHALL land on the company app, in a browser and through the command-line sign-in. A publish SHALL keep the address that the login returns to turned on. A publish whose settings would turn that address off SHALL stop before it changes the site, and SHALL name the setting to add.

#### Scenario: Sign in after a publish
- **WHEN** the owner signs in at admin.relayeverything.com after a publish
- **THEN** the browser shows the company app, not a *There is nothing here yet* page, and the command-line sign-in gets its token

#### Scenario: Settings that would turn the address off
- **WHEN** a publish runs with a custom domain in the live settings and no setting that keeps the workers.dev address on
- **THEN** the check before the publish stops it and names `workers_dev`

### Requirement: The company app and Relay Everything have their own addresses

The company app SHALL answer at admin.relayeverything.com behind the same login as before. Relay Everything's open server SHALL answer at app.relayeverything.com, where a person can sign up. A publish of either SHALL keep both addresses where they are.

#### Scenario: The company app stays private
- **WHEN** a person with no login opens admin.relayeverything.com
- **THEN** the site asks for the company login and shows no data

#### Scenario: A publish keeps the open address
- **WHEN** the company app is published
- **THEN** app.relayeverything.com still shows the Relay Everything sign-in
