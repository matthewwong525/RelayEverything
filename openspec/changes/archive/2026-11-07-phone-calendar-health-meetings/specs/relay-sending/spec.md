## MODIFIED Requirements

### Requirement: Health and location history only while sending

The app SHALL read health samples, calendar events for sending, and record location history only while sending is on, and SHALL keep no copy of any of them while sending is off.

#### Scenario: Sending is off
- **WHEN** the person has never turned sending on
- **THEN** the app asks for no health, calendar or background-location permission, and stores no samples, events or points

#### Scenario: Sending turned off with uploads waiting
- **WHEN** the person turns sending off while health samples, calendar events or location points are still waiting to go
- **THEN** the app deletes them, stops reading health and the calendar and recording location, and keeps every note
