# relay-app-publish Specification

## Purpose

Keep the public relay-app repository equal to the published phone app folder, and never let a key or private note reach it.

## Requirements

### Requirement: Publishing copies only the app folder

After a change is published to `main`, the public `matthewwong525/relay-app` repository SHALL hold exactly the files tracked under `mobile/` at that commit, at its root, and nothing else from the ring's project.

#### Scenario: A publish changes the app
- **WHEN** a published `main` has a different `mobile/` from relay-app's latest commit
- **THEN** relay-app gets one new commit whose files equal that `mobile/` folder

#### Scenario: A publish leaves the app alone
- **WHEN** `mobile/` on the published `main` equals relay-app's latest commit
- **THEN** nothing is pushed

### Requirement: Keys and private notes never leave

The copy SHALL be refused, with nothing pushed, when any file under `mobile/` is a secret-shaped file (Apple signing files such as `.p8`, `.p12`, `.cer` and provisioning profiles included), a private note, or contains a key or a value from the project's private `.env`.

#### Scenario: A key slipped into the app
- **WHEN** a file under `mobile/` contains a GitHub token or a value from `.env`
- **THEN** the copy stops before pushing and names the file, never the value

#### Scenario: An Apple key file in the app folder
- **WHEN** `mobile/` holds an App Store Connect `.p8` key file
- **THEN** the copy stops before pushing and names the file

### Requirement: A branch can be built before publishing

The copy SHALL push to a named relay-app branch when asked, leaving `main` unchanged, so a change's phone builds can be checked before it is published.

#### Scenario: A pre-publish build
- **WHEN** the copy runs for a change's branch with a branch name
- **THEN** relay-app gets that branch and its `main` stays as it was
