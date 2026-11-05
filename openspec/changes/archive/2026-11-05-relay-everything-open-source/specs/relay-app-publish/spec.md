## REMOVED Requirements

### Requirement: Publishing copies only the app folder
**Reason**: The phone app now lives in the public RelayEverything repository; there is no separate copy.
**Migration**: relay-app gets a note pointing to RelayEverything and is archived.

### Requirement: Keys and private notes never leave
**Reason**: The whole repository is public now, so the guard covers every folder, not only `mobile/`.
**Migration**: `relay-open-source` requires the same check on every change and on the full history.

### Requirement: A branch can be built before publishing
**Reason**: A pull request in RelayEverything builds the phone app itself.
**Migration**: `relay-app-builds` covers pull-request builds.
