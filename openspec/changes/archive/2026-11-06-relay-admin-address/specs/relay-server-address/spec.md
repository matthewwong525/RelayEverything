## REMOVED Requirements

### Requirement: The private site answers at app.relayeverything.com
**Reason**: Its scenarios promised that old Access device keys work at app.relayeverything.com. That address is now the open Relay Everything server, and each device gets a new key there.
**Migration**: Make a new key on app.relayeverything.com with *Add a device*.

## ADDED Requirements

### Requirement: The company app and Relay Everything have their own addresses

The company app SHALL answer at admin.relayeverything.com behind the same login as before. Relay Everything's open server SHALL answer at app.relayeverything.com, where a person can sign up. A publish of either SHALL keep both addresses where they are.

#### Scenario: The company app stays private
- **WHEN** a person with no login opens admin.relayeverything.com
- **THEN** the site asks for the company login and shows no data

#### Scenario: A publish keeps the open address
- **WHEN** the company app is published
- **THEN** app.relayeverything.com still shows the Relay Everything sign-in

## MODIFIED Requirements

### Requirement: A sign-in finishes on the site after every publish

A person who signs in at admin.relayeverything.com SHALL land on the company app, in a browser and through the command-line sign-in. A publish SHALL keep the address that the login returns to turned on. A publish whose settings would turn that address off SHALL stop before it changes the site, and SHALL name the setting to add.

#### Scenario: Sign in after a publish
- **WHEN** the owner signs in at admin.relayeverything.com after a publish
- **THEN** the browser shows the company app, not a *There is nothing here yet* page, and the command-line sign-in gets its token

#### Scenario: Settings that would turn the address off
- **WHEN** a publish runs with a custom domain in the live settings and no setting that keeps the workers.dev address on
- **THEN** the check before the publish stops it and names `workers_dev`
