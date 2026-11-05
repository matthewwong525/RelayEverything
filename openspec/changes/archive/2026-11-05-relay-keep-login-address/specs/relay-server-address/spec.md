# Spec Delta

## ADDED Requirements

### Requirement: A sign-in finishes on the site after every publish

A person who signs in at app.relayeverything.com SHALL land on the Relay site, in a browser and through the command-line sign-in. A publish SHALL keep the address that the login returns to turned on. A publish whose settings would turn that address off SHALL stop before it changes the site, and SHALL name the setting to add.

#### Scenario: Sign in after a publish
- **WHEN** the owner signs in at app.relayeverything.com after a publish
- **THEN** the browser shows the Relay site, not a *There is nothing here yet* page, and the command-line sign-in gets its token

#### Scenario: Settings that would turn the address off
- **WHEN** a publish runs with a custom domain in the live settings and no setting that keeps the workers.dev address on
- **THEN** the check before the publish stops it and names `workers_dev`
