## MODIFIED Requirements

### Requirement: The whole project is public and licensed

Relay's whole project SHALL be one public GitHub repository, `matthewwong525/RelayEverything`, under the MIT license, with any copied library keeping its own license. Notes that aren't code (memory, company knowledge, notes, health and location data) and keys SHALL stay out of it.

#### Scenario: A stranger reads the code
- **WHEN** a person with no account opens the repository
- **THEN** they can read and clone every folder, and the license file says they may use, change and share it

#### Scenario: Vendored parts keep their terms
- **WHEN** the repository holds a library copied from another project
- **THEN** that library still carries its own license file
