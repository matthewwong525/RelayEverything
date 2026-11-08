# relay-app-releases Specification

## Purpose
Release the Relay Everything phone app from a version tag on `main`: test it, submit the iPhone app to App Store review, publish the signed Android file as the latest GitHub release, and write the release notes from the changes to `mobile/`.

## Requirements

### Requirement: A version tag on main releases the phone app

Pushing a tag `v<major>.<minor>.<patch>` on a commit that is on `main` SHALL release the phone app at that version with no other step: the tag SHALL set the app's version name, and no file in the repository needs a version edit. A tag that is not on `main`, is not in that form, or is not higher than the newest earlier `v*` tag SHALL stop the release before any build, with a message that says why.

#### Scenario: A tag on main
- **WHEN** a person pushes `v1.1.0` on a commit on `main`, and the newest earlier release tag is `v1.0.0`
- **THEN** the release builds version 1.1.0 of both apps and continues to the full test

#### Scenario: A tag that cannot release
- **WHEN** the tag is on a commit that is not on `main`, or its version is not higher than the last release
- **THEN** the run fails at once with the reason, and nothing is built, uploaded or published

### Requirement: The full test gates every store submission

A release SHALL send nothing to a store or a GitHub release until all of these pass on the tagged commit: the Flutter analyzer and tests, the signed Android build, the signed iPhone build with its voice-note speech check, and every step of the fixed iPhone simulator tour. The release SHALL NOT run the Claude part of the device check.

#### Scenario: Everything passes
- **WHEN** each check passes on the tagged commit
- **THEN** the release goes on to submit the iPhone app and publish the Android file

#### Scenario: One check fails
- **WHEN** any check fails, such as one step of the simulator tour
- **THEN** no App Store submission and no GitHub release is made from that tag

### Requirement: A release submits the iPhone app for App Store review

After the full test passes, the release SHALL submit the tagged iPhone build to App Store review with the release notes as its *What's New* text, except on the app's first App Store version, where Apple takes none, and SHALL ask Apple to put it live as soon as it is approved. It SHALL NOT change the App Store listing's description, screenshots or privacy answers. Running the release job again for the same tag SHALL NOT submit a second time.

#### Scenario: Submitted for review
- **WHEN** the full test passes for `v1.1.0` and the App Store Connect keys are set
- **THEN** App Store Connect shows version 1.1.0 waiting for review, with automatic release and the release notes as *What's New*

#### Scenario: A rerun of the same tag
- **WHEN** the release job runs again after version 1.1.0 was already submitted
- **THEN** it does not submit again and goes on to the GitHub release

### Requirement: A release publishes the signed Android file as the latest GitHub release

The release SHALL publish a RelayEverything GitHub release named for the tag, titled *Relay Everything <version>*, marked latest, with the Android app file signed with the upload key. A release SHALL refuse to publish a file signed with a debug key.

#### Scenario: Published
- **WHEN** the iPhone app is submitted for `v1.1.0`
- **THEN** the release `v1.1.0` holds the signed Android file and the website's latest-release link opens it

#### Scenario: No upload key
- **WHEN** the Android upload key secrets are missing
- **THEN** the release fails with a message that names them, and publishes no Android file

### Requirement: Release notes come from the changes to the phone app

The release notes SHALL list each pull request merged into `main` since the previous `v*` tag whose commit changed `mobile/`, by its title and number, grouped by its labels, with a link to the full comparison between the two tags. Commits with no pull request SHALL be listed by their first line. Changes outside `mobile/` SHALL NOT be listed. The first release, with no earlier tag, SHALL list the changes since the start of `mobile/`.

#### Scenario: Notes for a release
- **WHEN** three pull requests changed `mobile/` and two changed only the server since `v1.0.0`
- **THEN** the notes for `v1.1.0` list the three, and not the two

### Requirement: Each released pull request is marked

The release SHALL add the label *released* to each pull request in its notes and comment on it once with the version and the release's link. A rerun SHALL NOT add a second comment.

#### Scenario: Marked once
- **WHEN** the release for `v1.1.0` publishes, then its job runs again
- **THEN** each listed pull request has the label *released* and exactly one comment for 1.1.0

### Requirement: Betas after a release use the next version

A build from `main` SHALL use the version after the newest `v*` tag, with its patch number one higher, so TestFlight accepts it after that version is live; with no `v*` tag yet, it SHALL use the version in `pubspec.yaml`.

#### Scenario: A beta after a release
- **WHEN** `v1.1.0` is the newest release tag and a change lands on `main`
- **THEN** its TestFlight build and Android pre-release are version 1.1.1
