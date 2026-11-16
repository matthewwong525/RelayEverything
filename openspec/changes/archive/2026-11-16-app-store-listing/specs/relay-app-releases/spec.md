## MODIFIED Requirements

### Requirement: A release submits the iPhone app for App Store review

After the full test passes, the release SHALL first send the App Store page kept in the repository, its words, screenshots, categories and age rating, and then submit the tagged iPhone build to App Store review with the release notes as its *What's New* text, except on the app's first App Store version, where Apple takes none, and SHALL ask Apple to put it live as soon as it is approved. It SHALL NOT change the privacy answers. A release check SHALL verify the page with Apple and send none of it. Running the release job again for the same tag SHALL NOT submit a second time.

#### Scenario: Submitted for review
- **WHEN** the full test passes for `v1.1.0` and the App Store Connect keys are set
- **THEN** App Store Connect shows version 1.1.0 waiting for review, with automatic release, the release notes as *What's New*, and the page's words and screenshots from the tagged commit

#### Scenario: A rerun of the same tag
- **WHEN** the release job runs again after version 1.1.0 was already submitted
- **THEN** it does not submit again and goes on to the GitHub release

#### Scenario: A release check
- **WHEN** a person runs the release check from `main`
- **THEN** Apple checks the page from the repository, and App Store Connect shows no change to the page
