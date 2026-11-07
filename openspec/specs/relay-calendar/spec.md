# relay-calendar Specification

## Purpose
Send the events of the phone's own calendars to the person's space while sending is on, and serve them to the AI connector, the web API, the day summary and webhooks.

## Requirements

### Requirement: The phone sends its calendars while sending is on

The phone app SHALL read the events of every calendar on the phone, read-only, and SHALL send them to the person's space only while sending and the calendar switch are on. The first send SHALL cover the last 90 days and the next 90 days; later sends SHALL carry only new, changed and removed events in that window. The person SHALL be able to turn single calendars off, and the events of a calendar turned off SHALL be removed from the space at the next send. The app SHALL never add, change or delete an event on the phone.

#### Scenario: First send
- **WHEN** the person turns the calendar on with sending on and allows the phone's calendar
- **THEN** the space gets the events from 90 days ago to 90 days ahead from every calendar on the phone, each with title, start, end, all-day mark, place, notes, calendar name and people

#### Scenario: An event moves and another is cancelled
- **WHEN** a meeting moves to the next day and another is deleted on the phone
- **THEN** after the next send the space shows the new time for the first and no longer lists the second

### Requirement: Calendar events are stored once and read like other data

The space SHALL keep one copy of each event occurrence per device, however often it is sent, and SHALL offer the events to the AI connector, the web API, the day summary and the webhooks that take the calendar, from the person's own space only.

#### Scenario: The same events sent twice
- **WHEN** a phone resends a batch of events after losing signal
- **THEN** each event is stored once, and the answer says how many were new or changed

#### Scenario: A recurring meeting
- **WHEN** a weekly meeting repeats on the phone
- **THEN** the space keeps each occurrence in the window as its own event with its own start
