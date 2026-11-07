# Spec Delta

## Purpose

Lets a person send the photos they take on their phone to their own Relay Everything space, where their AI can read them through the connector, and delete them there.

## ADDED Requirements

### Requirement: Photos go only while the person has them on

The phone app SHALL read the photo library and send photos only while both *Send to Relay Everything* and *Photos* are on. *Photos* SHALL be off by default and SHALL ask for photo access only when turned on. Turning either switch off SHALL stop reading the library and delete the photos still waiting on the phone.

#### Scenario: Photos never turned on
- **WHEN** a person sends notes, health and location but never turns *Photos* on
- **THEN** the app asks for no photo access and no photo leaves the phone

#### Scenario: Photos turned off with uploads waiting
- **WHEN** the person turns *Photos* off while photos are still waiting to go
- **THEN** the app deletes the waiting copies, sends no more photos, and leaves the photos already sent on the server

### Requirement: Only new photos, small, with their time and place

The app SHALL send only photos taken after *Photos* was turned on, never the library from before. It SHALL send a copy no larger than 1,600 pixels on its long side, with the time the photo was taken and, when the photo has one, the place it was taken. Each photo SHALL be stored once per device, however often the phone sends it.

#### Scenario: Turned on with a full library
- **WHEN** a person with thousands of photos turns *Photos* on and then takes two photos
- **THEN** only those two photos go, each with its time and place

#### Scenario: A photo sent twice after losing signal
- **WHEN** the phone sends a photo again after the first try lost its answer
- **THEN** the space holds that photo once

### Requirement: Photos wait for Wi-Fi unless the person allows mobile data

Photos SHALL go only over Wi-Fi, unless the person turns on *Send photos on mobile data*. A photo waiting for Wi-Fi SHALL NOT hold back notes, health or location.

#### Scenario: On mobile data
- **WHEN** the phone is on mobile data with photos waiting and mobile data not allowed
- **THEN** notes, health and location still go, and the photos go at the next round on Wi-Fi

### Requirement: Each photo is sealed in its person's space

The server SHALL store each photo only in the space of the person whose key sent it, sealed with that space's own file key, the same as a ring recording. A photo SHALL open only through that person's page session or their AI app. Deleting the account SHALL delete every photo.

#### Scenario: Another person's photo id
- **WHEN** Ben's AI app asks for a photo by the id of one of Ana's photos
- **THEN** it gets no photo

### Requirement: The page counts photos and deletes them all

The person's Relay Everything page SHALL show how many photos their space holds and SHALL offer *Delete all photos*, which asks to confirm, says it can't be undone, and deletes every photo and its row. The page SHALL NOT show the photos themselves.

#### Scenario: Delete all photos
- **WHEN** the person confirms *Delete all photos*
- **THEN** the count shows none, the AI app finds no photo, and notes, health and places stay
