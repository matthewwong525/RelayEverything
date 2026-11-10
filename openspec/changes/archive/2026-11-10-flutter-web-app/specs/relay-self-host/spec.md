## ADDED Requirements

### Requirement: An install serves the web app without Flutter

An install and its update SHALL serve the Flutter web app built from the same commit as its server code, and SHALL NOT ask the person to install Flutter. When no build for that commit is found, the install SHALL stop before it changes anything and say why.

#### Scenario: An update brings the new web app
- **WHEN** a person updates an install to a released version
- **THEN** the page shows that version's web app, with no Flutter on their computer

#### Scenario: No build for the commit
- **WHEN** a person installs from a commit that has no web build
- **THEN** the install stops, the old server stays live, and the AI says which release to use
