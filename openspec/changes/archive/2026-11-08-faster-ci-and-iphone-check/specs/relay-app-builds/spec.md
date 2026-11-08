## MODIFIED Requirements

### Requirement: Each pushed version is checked and built

A pull request or push to RelayEverything that changes `mobile/` SHALL run the Flutter analyzer and tests, and build the Android app file and, when the App Store Connect keys are set, the signed iPhone app. On a branch the builds MAY start before the tests finish; a build for `main` or a release SHALL start only after the tests pass. Only a push to `main` SHALL upload an iPhone build to TestFlight or publish the Android file as a RelayEverything pre-release; a branch, pull request or fork SHALL upload and publish nothing. A `main` build SHALL upload and publish only when no newer commit on `main` changes `mobile/`, so TestFlight and the pre-releases never receive an older build after a newer one. Every build SHALL get a build number higher than every build before it, on any branch or tag.

#### Scenario: A published change
- **WHEN** a change to `mobile/` is published to `main` and is the newest change to `mobile/` there
- **THEN** a new RelayEverything pre-release, not marked latest, holds the Android app file, and TestFlight receives a build when the Apple keys are set

#### Scenario: A pre-publish branch
- **WHEN** a change's branch or pull request changes `mobile/`
- **THEN** the Android app file is kept with the run, the iPhone app builds where the keys allow, both builds start without waiting for the tests, and nothing goes to TestFlight or to a release

#### Scenario: A failing test
- **WHEN** a Flutter test fails
- **THEN** no release or TestFlight build is made from that commit, and the run shows failed even if its branch builds passed

#### Scenario: A newer change lands first
- **WHEN** a `main` build finishes after a newer commit that changes `mobile/` is already on `main`
- **THEN** it uploads nothing and publishes nothing, and says that a newer build follows
