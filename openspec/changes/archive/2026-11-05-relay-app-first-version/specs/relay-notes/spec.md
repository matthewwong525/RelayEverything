# Spec Delta

## Purpose

Receive every note Matthew captures, from the Pebble ring or typed on a phone, exactly once, with its words, recording and place.

## ADDED Requirements

### Requirement: Signed ring notes are received once

Relay SHALL accept a Pebble Index webhook (version 1) only when its HMAC-SHA256 signature matches the saved signing secret and its timestamp is within five minutes, and SHALL store each `X-Index-Delivery` at most once.

#### Scenario: A ring note arrives twice
- **WHEN** Pebble's app sends the same signed delivery again after a timeout
- **THEN** Relay answers success both times and keeps one note with its transcript and audio

#### Scenario: A forged or stale request
- **WHEN** a request has a wrong signature, an unsupported version, or a timestamp over five minutes old
- **THEN** Relay refuses it and stores nothing

### Requirement: Every note carries a place when one is known

A typed note SHALL keep the location the phone sent with it; a ring note SHALL take the nearest location-history point within 10 minutes of its recording time, or none.

#### Scenario: A ring note during a walk
- **WHEN** a ring note is recorded 3 minutes after a stored location point
- **THEN** the timeline shows it at that point's place
