## ADDED Requirements

### Requirement: The App Store page lives in the repository

The iPhone app's App Store page SHALL be kept as files in the repository: its name *Relay Everything*, subtitle, description, keywords, promotional text, primary and secondary category, age rating answers, support link, marketing link, privacy link, copyright line, reviewer note, and screenshots for iPhone, iPad and Apple Watch. The privacy link SHALL be the website's live Privacy page. No file SHALL hold the reviewer contact's email or phone, a key, or any other private detail, because the repository is public. A check SHALL refuse a page text that is over Apple's length limit, a missing required file, a screenshot of a size Apple does not take, and a bare *Relay* in place of *Relay Everything*.

#### Scenario: A person changes the description
- **WHEN** a person edits the description file and the change is published
- **THEN** the next release sends the new description to the App Store page, with no edit in App Store Connect

#### Scenario: A text over Apple's limit
- **WHEN** the keywords file holds more than 100 characters, or the subtitle more than 30
- **THEN** the repository's checks fail and name the file and its limit

### Requirement: Store screenshots come from the real app on simulators

A workflow started by hand SHALL open the app on the largest iPhone and iPad simulators Apple asks for, and the watch app on a watch simulator, with sample notes made by the workflow itself, and SHALL keep the plain screenshots it takes, with no added words, as a file of the run. The screenshots SHALL show no person's real data.

#### Scenario: New screenshots
- **WHEN** a person runs the screenshot workflow from `main`
- **THEN** the run keeps iPhone, iPad and Apple Watch screenshots at sizes App Store Connect takes, ready to replace the ones in the repository

### Requirement: The privacy answers are recorded in the repository

The answers to Apple's App Privacy questions SHALL be kept as one file in the repository, and App Store Connect SHALL show the same answers. They SHALL say that no data is used to track the person, and SHALL list each kind of data the app sends as linked to the person and used only to run the app.

#### Scenario: The app starts to collect a new kind of data
- **WHEN** a change makes the app send a kind of data the answers do not list
- **THEN** the same change updates the answers file, and the answers in App Store Connect are updated to match before the next release
