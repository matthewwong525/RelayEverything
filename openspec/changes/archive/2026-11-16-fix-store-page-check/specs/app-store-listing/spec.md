## ADDED Requirements

### Requirement: The release check reads the same page files the release sends
The release check SHALL check the store page files that a release would send, and SHALL fail only for a fault in those files or in App Store Connect, never because it looked for them in another folder.

#### Scenario: Correct page files
- **WHEN** a person runs the release check from `main` and the page files have the words and the screenshots for every device
- **THEN** the App Store page step passes, says the page is ready, and sends nothing

#### Scenario: A missing language folder
- **WHEN** App Store Connect's primary language has no folder of page words in the repository
- **THEN** the App Store page step fails and names the language
