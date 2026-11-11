## MODIFIED Requirements

### Requirement: Search finds notes on the phone

The notes list SHALL have a search field that shows only the notes whose words or file names hold the typed text, ignoring capital letters. Search SHALL read only the phone and SHALL make no network call.

#### Scenario: Search with no signal

- **WHEN** the phone has no connection and the person types *dentist* in *Search*
- **THEN** only the notes that hold *dentist* show, and no request leaves the phone

#### Scenario: Nothing matches

- **WHEN** the person searches for words no note holds
- **THEN** the list says no note holds them, and *Cancel* shows every note again
