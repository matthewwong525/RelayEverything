## Purpose

The *Share to Relay Everything* button: from any app on an iPhone or an Android phone, a person keeps a link, text, photos or files as one note, and it follows their *Send to Relay Everything* setting.

## ADDED Requirements

### Requirement: Share from any app

The phone app SHALL appear in the system share list on iPhone and on Android for web links, text, images and other files. Choosing it SHALL open a card over the sharing app that shows the shared items and takes optional words. *Save* SHALL keep one note and return the person to the sharing app; *Cancel* SHALL keep nothing.

#### Scenario: Share a web page

- **WHEN** the person shares a page from a browser, adds the words "read later" and taps *Save*
- **THEN** one note is kept whose text holds "read later", the page's title and its link, with the time of the share and no place

#### Scenario: Cancel

- **WHEN** the person taps *Cancel* on the card
- **THEN** no note is kept and nothing is sent

### Requirement: Shared files follow the note file limits

Shared images and files SHALL become files on the note, at most 10 per note and at most 25 MB each. An item past either limit SHALL be left out, and the card SHALL name what it left out before *Save*. A share with nothing left and no words SHALL NOT be saved.

#### Scenario: Too many photos

- **WHEN** the person shares 12 photos
- **THEN** the note holds the first 10 and the card says 2 were left out

#### Scenario: Only a file that is too big

- **WHEN** the person shares one 40 MB video and adds no words
- **THEN** the card says the video is too big and *Save* is off

### Requirement: Sending off keeps the share on the phone

With *Send to Relay Everything* off, or with no device key, the share card SHALL make no network call. The note SHALL show in the phone's timeline from the next open, and SHALL be sent later only as any unsent note is, through *Send them*.

#### Scenario: Share with sending off

- **WHEN** sending is off and the person saves a share
- **THEN** the card makes no network call, says the note is kept on this phone, and the note is in the timeline at the next open

### Requirement: Sending on sends at once

With sending on, the share card SHALL send the note with the phone's own device key at once, then its files. The card SHALL close when everything is stored, or after about 20 seconds, or at once with no signal. Whatever the card did not send, the app SHALL send at its next open or hourly round. A note or file sent twice SHALL be stored once, and the person's webhooks SHALL get the note as they get a typed note.

#### Scenario: Sent from the card

- **WHEN** sending is on, the phone has signal and the person saves a share with one photo
- **THEN** the note and the photo are in the person's space before the card closes, and the webhooks get the note once

#### Scenario: A big file does not finish

- **WHEN** sending is on and a file does not finish within about 20 seconds
- **THEN** the card closes saying the note is kept and sends later, and the app sends the file at its next open without storing the note twice

### Requirement: The device key stays on the phone

The share card SHALL use only the device key the phone already holds. It SHALL NOT ask for, show, or store a new key, and SHALL NOT read data from the person's space.

#### Scenario: Key turned off on the page

- **WHEN** the person turned the phone's key off and then saves a share with sending on
- **THEN** the note is kept on the phone and the app shows the refused key as it does for any refused send
