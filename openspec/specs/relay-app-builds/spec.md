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

### Requirement: iPhone builds sign with one saved certificate

The iPhone build SHALL sign the app and its share extension with the one Apple Distribution certificate kept in the repository secrets `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD`, and SHALL NOT make a new signing certificate on Apple's account. It SHALL get the App Store profiles for `com.matthewwong525.relayApp` and `com.matthewwong525.relayApp.share` from Apple with the App Store Connect key, using an existing valid profile for that certificate and making one only when none is valid. The certificate, its password and the profiles SHALL NOT be in the repository.

#### Scenario: Many builds in a row
- **WHEN** the iPhone build runs any number of times on new build machines
- **THEN** the count of certificates on the Apple account does not change, and each build reaches TestFlight

#### Scenario: Certificate secrets missing
- **WHEN** the App Store Connect secrets are set but `IOS_DIST_CERT_P12` or `IOS_DIST_CERT_PASSWORD` is not
- **THEN** the iPhone job ends with a notice that names the missing secret and builds nothing

#### Scenario: A profile is missing or old
- **WHEN** Apple has no valid App Store profile for one of the two bundle ids and the saved certificate
- **THEN** the build makes that profile, signs with it, and the next build uses the same one

#### Scenario: Renewing the certificate
- **WHEN** a person runs the certificate script on a computer that has the App Store Connect key
- **THEN** Apple makes one Apple Distribution certificate, and the script stores it and a new password in the repository secrets and the git-ignored `.env`, printing neither value
