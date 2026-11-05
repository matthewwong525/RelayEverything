## ADDED Requirements

### Requirement: The whole project is public and licensed

Relay's whole project SHALL be one public GitHub repository, `matthewwong525/RelayEverything`, under the MIT license, with vendored libraries keeping their own licenses. Notes that aren't code (memory, company knowledge, notes, health and location data) and keys SHALL stay out of it.

#### Scenario: A stranger reads the code
- **WHEN** a person with no account opens the repository
- **THEN** they can read and clone every folder, and the license file says they may use, change and share it

#### Scenario: Vendored parts keep their terms
- **WHEN** a person reads `vendor/`
- **THEN** each library there still carries its own license file

### Requirement: History is scanned before the repository opens

Before the repository becomes public, every file in every past commit SHALL be checked for key-shaped text, values from the project's private settings, secret-shaped files (Apple signing files included) and private notes. Any hit SHALL stop the move with nothing made public, naming the file and commit, never the value.

#### Scenario: A clean history
- **WHEN** no past commit holds a key, private value, secret file or private note
- **THEN** the full history is pushed and the repository can be made public

#### Scenario: A key in an old commit
- **WHEN** an old commit holds a key that a later commit removed
- **THEN** the move stops, names that file and commit, and the repository stays private

### Requirement: Every change is checked on GitHub

Each change SHALL be saved as a pull request whose checks run on GitHub Actions, and the same key and private-note check SHALL run on it. A pull request from outside SHALL run its checks with no project keys and SHALL never deploy.

#### Scenario: A key slips into a change
- **WHEN** a pull request adds a file that holds a key or a secret-shaped file
- **THEN** its checks fail, naming the file, never the value, and it can't be published

#### Scenario: An outside pull request
- **WHEN** someone without write access opens a pull request
- **THEN** its tests run, and no secret is passed to it and nothing is deployed
