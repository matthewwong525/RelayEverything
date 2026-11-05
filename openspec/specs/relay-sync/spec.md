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
