## REMOVED Requirements

### Requirement: Settings shows when health and places last went

**Reason**: Health and Location history move out of Settings into their own folders on Home.
**Migration**: The same status shows on each folder's page, by the requirement added below.

## ADDED Requirements

### Requirement: The Health and Location folders show when each last went

While sending is on, the *Health* and *Location* folders SHALL show when each last reached the person's space and how many of each wait to send.

#### Scenario: Sending stalls

- **WHEN** the phone has had no network since morning
- **THEN** the *Health* and *Location* folders show the morning time and the number of readings and points waiting
