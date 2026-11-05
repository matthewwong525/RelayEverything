# Spec Delta

## Purpose

Turn each version of `mobile/` that reaches relay-app into a checked Android app file and an iPhone TestFlight build.

## ADDED Requirements

### Requirement: Each pushed version is checked and built

A push to relay-app SHALL run the Flutter analyzer and tests, then upload an iPhone build to TestFlight and build the Android app file; only `main` SHALL publish that file as a public release.

#### Scenario: A published change
- **WHEN** a publish copies a changed `mobile/` to relay-app's `main`
- **THEN** a new release holds the Android app file and TestFlight receives a new build

#### Scenario: A pre-publish branch
- **WHEN** a change's branch is pushed to relay-app
- **THEN** TestFlight receives a build, the Android app file is kept with the run, and no public release is made

#### Scenario: A failing test
- **WHEN** a Flutter test fails
- **THEN** no release or TestFlight build is made from that commit
