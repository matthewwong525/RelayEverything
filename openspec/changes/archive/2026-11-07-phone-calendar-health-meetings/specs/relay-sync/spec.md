## ADDED Requirements

### Requirement: Health covers more types and 90 days of history

The phone app SHALL send, besides steps, heart rate, sleep and workouts: weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle flow, mindful minutes where the phone gives them, and water, each in one fixed unit. The first read after health is turned on SHALL cover the last 90 days, newest first, spread over several rounds; a phone that already sent health SHALL do the same 90-day read once after the update. A type the person did not allow in the phone's health permission SHALL be skipped with no error.

#### Scenario: Day one
- **WHEN** a person turns health on and the phone has a year of weight and heart readings
- **THEN** within a few rounds the space holds the last 90 days of every allowed type, and nothing older

#### Scenario: One type refused
- **WHEN** the person allows every type but cycle
- **THEN** the other types are sent, and no cycle data is read or sent
