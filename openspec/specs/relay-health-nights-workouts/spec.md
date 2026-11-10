# relay-health-nights-workouts Specification

## Purpose
Give a person's sleep as nights, with times and stages, and each workout with its kind, distance and calories, made on their own phone, so their AI, the API and their webhooks can answer questions about sleep and exercise.

## Requirements

### Requirement: The phone turns sleep into nights

While sending and *Health* are on, the phone SHALL group the sleep readings of each source into nights, a reading more than 2 hours after the last starting a new night. A night SHALL give its start and end, when the person fell asleep and woke where the readings show it, and its minutes asleep, in core, deep and REM sleep, and awake. Overlapping readings of one source SHALL never count twice. The phone SHALL still send the sleep minutes it sent before, so the day's sleep total does not change.

#### Scenario: A watch night with stages
- **WHEN** a watch writes a night from 23:05 to 06:55 with core, deep, REM and awake stages
- **THEN** the phone sends one night with those times and each stage's minutes, and the day's sleep total stays as before

#### Scenario: A watch and the phone's bedtime both write the night
- **WHEN** the phone's bedtime writes in bed from 23:00 and a watch writes stages from 23:05
- **THEN** each source gives its own night, and no stage minutes are added across them

### Requirement: Each night keeps its stage timeline

A night SHALL also carry its stages in time order, each with its start and end, so a person or their AI can see when each stage came, not only how long. Overlapping readings SHALL give no overlapping steps. A night whose source gives no stages SHALL carry an empty timeline. The night's stage minutes SHALL not change with the timeline.

#### Scenario: When was my deep sleep
- **WHEN** the AI reads last night with its timeline
- **THEN** it gets each step, such as core from 23:20, deep from 00:10 and REM from 01:05, and the steps add up to the night's stage minutes

#### Scenario: A phone's bedtime only
- **WHEN** the only sleep that night is the phone's in-bed time
- **THEN** the night has its bedtime and an empty timeline

### Requirement: Each workout keeps its kind, distance and calories

The phone SHALL send each workout with its kind, and its distance and calories when the phone has them. On Android, it SHALL ask once for permission to read distance and calories; Health Connect gives the app workouts only with them, so after a refusal the phone SHALL send no Android workouts, as before, and show no error.

#### Scenario: A run
- **WHEN** the person records a 32-minute run of 5.1 km and 410 kcal
- **THEN** the workout goes as running, 32 minutes, 5,100 m and 410 kcal

#### Scenario: Calories refused on Android
- **WHEN** the person refuses distance and calories in Health Connect
- **THEN** the phone sends no workouts from Android, sends the other types, and no error shows

### Requirement: Late sleep and workouts are not lost or sent again

Each round SHALL read sleep and workouts from at least the last 36 hours, so a night or workout written after it ended is sent whole. A night or workout the phone sent in the last 48 hours and that did not change SHALL not be sent again.

#### Scenario: A watch writes the night at wake
- **WHEN** a round ran at 03:00 and the watch writes the night from 23:05 to 06:55 at 07:00
- **THEN** the next round sends the whole night, from 23:05

#### Scenario: Nothing changed
- **WHEN** a round reads a night it already sent, with the same times and minutes
- **THEN** it sends nothing for that night, also to the person's own webhook

### Requirement: The last 90 days are redone once

After the update, a phone that already sent health SHALL read the last 90 days of sleep and workouts again once, a week each round, newest first, and send their nights and full workouts. A workout already on the server SHALL gain its kind, distance and calories, and sleep readings the server missed SHALL be added; nothing already kept SHALL be counted twice.

#### Scenario: A workout from last month
- **WHEN** a run from 30 days ago is on the server with its minutes only
- **THEN** after the redo reaches that week, the server's row has its kind, distance and calories, and the day's workout count is the same

### Requirement: Nights and workouts go where health goes

Nights and workout details SHALL go where the phone's health goes: to the person's Relay Everything space and from there only to webhooks ticked for *Health*, or, when the person picked their own webhook for health, only there. A resend that changes nothing SHALL wake no webhook. Health that goes only to the person's own webhook SHALL not reach the server.

#### Scenario: A webhook not ticked for Health
- **WHEN** a night arrives and the person has one webhook ticked for *Health* and one not
- **THEN** only the ticked webhook gets the night

#### Scenario: Only my own webhook
- **WHEN** the person picked *Only my own webhook* for health
- **THEN** the night and the full workout go straight to their webhook, and the server gets neither

### Requirement: The AI and the API read nights and workouts

The AI connector and the `/v1/` API SHALL give nights and workouts over a time range, newest first, and a day's summary SHALL add the nights that ended that day and the day's workouts, keeping every field it had. Where nights overlap, a read SHALL give the one with the most minutes asleep. Every read SHALL stay read-only, and a phone key SHALL not read them.

#### Scenario: How did I sleep this week
- **WHEN** the AI reads nights for the last 7 days
- **THEN** it gets up to 7 nights, each with its times and stage minutes, one per night

#### Scenario: A day from before the update
- **WHEN** the AI reads the summary of a day that only an old phone sent
- **THEN** it gets the same totals as before, workouts with no kind, and no night
