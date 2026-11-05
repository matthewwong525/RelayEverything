# Spec Delta

## Purpose

Keep every Relay note on the phone unless the person chooses to send, and send only what they chose.

## ADDED Requirements

### Requirement: The app works offline by default

A newly installed Relay phone app SHALL let the person write and read notes with no key, no server and no connection, and SHALL make no network request while sending is off.

#### Scenario: First open with no key
- **WHEN** the person opens the app for the first time and writes a note
- **THEN** the note is saved and shown in the timeline, and the app asks for no key

#### Scenario: A week of notes with sending off
- **WHEN** the person writes notes, pins them, and opens Settings with sending off
- **THEN** the app sends nothing to any server and looks up no place names

### Requirement: Health and location history only while sending

The app SHALL read health samples and record location history only while sending is on, and SHALL keep no copy of either while sending is off.

#### Scenario: Sending is off
- **WHEN** the person has never turned sending on
- **THEN** the app asks for no health or background-location permission and stores no samples or points

#### Scenario: Sending turned off with uploads waiting
- **WHEN** the person turns sending off while health samples or location points are still waiting to go
- **THEN** the app deletes them, stops reading health and recording location, and keeps every note

### Requirement: Earlier notes go only when the person says so

When the person turns sending on and notes exist that never went to the server, the app SHALL ask whether to send them, and SHALL send them only on a yes.

#### Scenario: Only new notes
- **WHEN** the person turns sending on with 42 unsent notes and picks only new notes
- **THEN** none of the 42 is sent, and notes written after that are sent

#### Scenario: Turned on again later
- **WHEN** the person turns sending on again after a time with it off
- **THEN** the app asks again about every note that never went to the server

### Requirement: Turning sending off keeps what exists

Turning sending off SHALL stop all sending, keep every note on the phone, and leave the server's copy untouched.

#### Scenario: Off and on again
- **WHEN** the person turns sending off and later back on
- **THEN** the server still holds the notes sent before, and the phone sends again without a new key
