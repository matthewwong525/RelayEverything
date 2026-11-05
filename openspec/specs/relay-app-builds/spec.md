# relay-app-builds Specification

## Purpose
Turn each version of `mobile/` in RelayEverything into a checked Android app file and an iPhone TestFlight build.

## Requirements

### Requirement: Each pushed version is checked and built

A pull request or push to RelayEverything that changes `mobile/` SHALL run the Flutter analyzer and tests, then build the Android app file and, when the App Store Connect keys are set, upload an iPhone build to TestFlight; only `main` SHALL publish the Android file as a public release of RelayEverything.

#### Scenario: A published change
- **WHEN** a change to `mobile/` is published to `main`
- **THEN** a new RelayEverything release holds the Android app file, and TestFlight receives a build when the Apple keys are set

#### Scenario: A pre-publish branch
- **WHEN** a change's pull request changes `mobile/`
- **THEN** the Android app file is kept with the run, and no public release is made

#### Scenario: A failing test
- **WHEN** a Flutter test fails
- **THEN** no release or TestFlight build is made from that commit
