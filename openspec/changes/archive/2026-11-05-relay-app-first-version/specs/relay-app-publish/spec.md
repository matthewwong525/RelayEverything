# Spec Delta

## MODIFIED Requirements

### Requirement: Keys and private notes never leave

The copy SHALL be refused, with nothing pushed, when any file under `mobile/` is a secret-shaped file (Apple signing files such as `.p8`, `.p12`, `.cer` and provisioning profiles included), a private note, or contains a key or a value from the project's private `.env`.

#### Scenario: A key slipped into the app
- **WHEN** a file under `mobile/` contains a GitHub token or a value from `.env`
- **THEN** the copy stops before pushing and names the file, never the value

#### Scenario: An Apple key file in the app folder
- **WHEN** `mobile/` holds an App Store Connect `.p8` key file
- **THEN** the copy stops before pushing and names the file

## ADDED Requirements

### Requirement: A branch can be built before publishing

The copy SHALL push to a named relay-app branch when asked, leaving `main` unchanged, so a change's phone builds can be checked before it is published.

#### Scenario: A pre-publish build
- **WHEN** the copy runs for a change's branch with a branch name
- **THEN** relay-app gets that branch and its `main` stays as it was
