# relay-app-builds Specification

## Purpose
Turn each version of `mobile/` in RelayEverything into a checked Android app file and an iPhone TestFlight build.

## Requirements

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

### Requirement: iPhone builds sign with one saved certificate

The iPhone build SHALL sign the app, its share extension, its watch app and the watch app's watch face button with the one Apple Distribution certificate kept in the repository secrets `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD`, and SHALL NOT make a new signing certificate on Apple's account. It SHALL get the App Store profiles for `com.matthewwong525.relayApp`, `com.matthewwong525.relayApp.share`, `com.matthewwong525.relayApp.watchkitapp` and `com.matthewwong525.relayApp.watchkitapp.widget` from Apple with the App Store Connect key, using an existing valid profile for that certificate and making one only when none is valid. It SHALL register a missing bundle id once with that key. The certificate, its password and the profiles SHALL NOT be in the repository.

#### Scenario: Many builds in a row
- **WHEN** the iPhone build runs any number of times on new build machines
- **THEN** the count of certificates on the Apple account does not change, and each build reaches TestFlight

#### Scenario: Certificate secrets missing
- **WHEN** the App Store Connect secrets are set but `IOS_DIST_CERT_P12` or `IOS_DIST_CERT_PASSWORD` is not
- **THEN** the iPhone job ends with a notice that names the missing secret and builds nothing

#### Scenario: A profile is missing or old
- **WHEN** Apple has no valid App Store profile for one of the bundle ids and the saved certificate
- **THEN** the build makes that profile, signs with it, and the next build uses the same one

#### Scenario: Renewing the certificate
- **WHEN** a person runs the certificate script on a computer that has the App Store Connect key
- **THEN** Apple makes one Apple Distribution certificate, and the script stores it and a new password in the repository secrets and the git-ignored `.env`, printing neither value

#### Scenario: The watch app ships with the iPhone app
- **WHEN** a `main` build reaches TestFlight
- **THEN** the build holds the watch app, and a person who installs it from TestFlight can install the watch app on their paired Apple Watch
