# relay-sync Specification

## Purpose
Bring a phone's health samples and location history into Relay without losing or doubling any, and give every device the same timeline back.

## Requirements

### Requirement: Uploads are idempotent

Health samples and location points SHALL be stored once per device, type and time range, however often a phone sends them.

#### Scenario: A sync retried after losing signal
- **WHEN** a phone resends a batch that was partly stored
- **THEN** Relay stores only the missing samples and reports how many it added

### Requirement: Capture works offline

The phone app SHALL keep notes, samples and points made offline and send them on the next successful sync.

#### Scenario: A note on the subway
- **WHEN** a note is typed with no connection
- **THEN** it shows at once in the timeline as waiting, and on the server after the next sync

### Requirement: A day's totals count each step once

The summary SHALL take, for steps and sleep, the largest source on each device, then the largest device.

#### Scenario: An iPhone and its Apple Watch
- **WHEN** an iPhone sends the same walk counted by the phone and by its watch
- **THEN** the day's steps are the larger count, not the sum

### Requirement: Health covers more types and 90 days of history

The phone app SHALL send, besides steps, heart rate, sleep and workouts: weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle flow, mindful minutes where the phone gives them, and water, each in one fixed unit. The first read after health is turned on SHALL cover the last 90 days, newest first, spread over several rounds; a phone that already sent health SHALL do the same 90-day read once after the update. A type the person did not allow in the phone's health permission SHALL be skipped with no error.

#### Scenario: Day one
- **WHEN** a person turns health on and the phone has a year of weight and heart readings
- **THEN** within a few rounds the space holds the last 90 days of every allowed type, and nothing older

#### Scenario: One type refused
- **WHEN** the person allows every type but cycle
- **THEN** the other types are sent, and no cycle data is read or sent
