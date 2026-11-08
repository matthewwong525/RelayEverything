---
title: Routes
description: Every route of the Relay Everything server, with its fields, made from the server's own route list.
---

<!-- Made by `npm run relay:api-doc` in app/ from app/worker/apps/relay/. Do not edit it by hand. -->

Each route sits under `https://<your-relay-server>/apps/relay/api/`. A device sends its key as
`Authorization: Bearer rek_…`, as [Keys](../keys/) shows; a person signs in on the page. A refused call answers `{ "error": { "code": "...", "message": "..." } }`; [Keys](../keys/#errors)
lists the codes.

## Store a typed note

`POST /apps/relay/api/notes` · `relay.notes-add` · writes · called by a phone key

Store a note typed on a Relay Everything phone, once per phone and clientId.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `clientId` | string | yes | The phone's own id for the note, so a resend is stored once. |
| `text` | string | yes | What the note says. It can be empty only when the note has files. |
| `createdAt` | integer | yes | When it was written, in Unix milliseconds. |
| `lat` | number | no | Where it was written: latitude. Send it with lon. |
| `lon` | number | no | Where it was written: longitude. Send it with lat. |
| `accuracy` | number | no | How sure the phone was of the place, in meters. |
| `place` | string | no | The place's name from the phone's address lookup. |
| `attachments` | array of object | no | The note's files, up to 10: only their names, types and sizes. Send each file's bytes after, with POST attachments. |
| `attachments[].id` | string | yes | The phone's own id for the file: its upload names it. |
| `attachments[].name` | string | yes | The file's name, such as `warranty.pdf`. |
| `attachments[].type` | string | yes | The file's content type, such as `application/pdf`; empty when the phone does not know it. |
| `attachments[].size` | integer | yes | The file's size in bytes, up to 25 MB. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |
| `added` | boolean | yes |  |

## Change a note

`PATCH /apps/relay/api/notes` · `relay.notes-edit` · writes · called by a phone key

Change the words of any note in your space, and list the files added since to a note this phone sent. The newer change wins: a change made before the note's last one gets 409. Webhooks get it as note.updated.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | no | The server's id for the note, as GET notes gives it: any note in your space. |
| `clientId` | string | no | Or the phone's own id for a note it sent, as POST notes sent it. |
| `text` | string | yes | What the note says now, in place of its words before. It can be empty only when the note has files. |
| `attachments` | array of object | no | All of the note's files now, up to 10. A file the server lacks is added: send its bytes after, with POST attachments. |
| `attachments[].id` | string | yes | The phone's own id for the file: its upload names it. |
| `attachments[].name` | string | yes | The file's name, such as `warranty.pdf`. |
| `attachments[].type` | string | yes | The file's content type, such as `application/pdf`; empty when the phone does not know it. |
| `attachments[].size` | integer | yes | The file's size in bytes, up to 25 MB. |
| `editedAt` | integer | no | When the phone made the change, in Unix ms; now when left out. A later time is taken as now. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |
| `updated` | boolean | yes | False when the words were the same and no file was new. |

### Errors

| Code | When |
|---|---|
| `not_found` | Your space has no note with this id, or this device sent no note with this clientId. |
| `older` | The note changed after this change was made, so the newer words stay: GET notes gives them. |
| `not_own` | Add a file only to a note this phone sent. |

## Read the notes changed since the last sync

`GET /apps/relay/api/notes` · `relay.notes-sync` · reads · called by a signed-in person or a phone key

Read each note added or changed after a change number, oldest change first. Ask again with `next` while `more` is true.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `since` | integer | no | The last page's `next`; 0 or left out for every note. |
| `limit` | integer | no | How many notes, 100 when left out. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `notes` | array of object | yes |  |
| `notes[].id` | string | yes |  |
| `notes[].clientId` | string or null | yes | The sending device's own id for the note. |
| `notes[].mine` | boolean | yes | True when the calling phone sent the note. |
| `notes[].source` | "ring" or "typed" | yes |  |
| `notes[].text` | string | yes |  |
| `notes[].recordedAt` | number | yes |  |
| `notes[].editedAt` | number or null | yes | When the note last changed, in Unix ms; null when never. |
| `notes[].device` | string | yes | The name of the device or way in that sent it, such as `Email`. |
| `notes[].audio` | boolean | yes |  |
| `notes[].place` | object or null | yes |  |
| `notes[].place.lat` | number | yes |  |
| `notes[].place.lon` | number | yes |  |
| `notes[].place.accuracy` | number or null | yes |  |
| `notes[].place.name` | string or null | yes |  |
| `notes[].place.from` | "phone" or "history" | yes |  |
| `notes[].attachments` | array of object | yes | The note's files, oldest first. |
| `notes[].attachments[].id` | string | yes |  |
| `notes[].attachments[].name` | string | yes |  |
| `notes[].attachments[].type` | string | yes |  |
| `notes[].attachments[].size` | number | yes |  |
| `notes[].attachments[].ready` | boolean | yes | True once the phone has sent the file: then GET attachment opens it. |
| `next` | number | yes | The change number to ask from next time. |
| `more` | boolean | yes | True when more changes wait after this page. |

## Store a phone's samples

`POST /apps/relay/api/health` · `relay.samples-add` · writes · called by a phone key

Store health samples from Apple Health or Health Connect, such as steps, sleep, weight and blood pressure, once per type, time span and source.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `samples` | array of object | yes | Up to 500 rows; a row stored before is skipped. |
| `samples[].type` | "steps" or "heart_rate" or "sleep" or "workout" or "weight" or "resting_heart_rate" or "hrv_sdnn" or "hrv_rmssd" or "blood_oxygen" or "blood_pressure_systolic" or "blood_pressure_diastolic" or "cycle_flow" or "mindful" or "water" | yes |  |
| `samples[].start` | integer | yes |  |
| `samples[].end` | integer | yes |  |
| `samples[].value` | number | yes |  |
| `samples[].unit` | string | yes |  |
| `samples[].source` | string | yes |  |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `received` | integer | yes |  |
| `added` | integer | yes |  |

## Store a phone's points

`POST /apps/relay/api/locations` · `relay.points-add` · writes · called by a phone key

Store the phone's location history, once per time. A note keeps the place it came with: a point gives no note a place.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `points` | array of object | yes | Up to 500 rows; a row stored before is skipped. |
| `points[].at` | integer | yes |  |
| `points[].lat` | number | yes |  |
| `points[].lon` | number | yes |  |
| `points[].accuracy` | number | yes |  |
| `points[].place` | string | no |  |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `received` | integer | yes |  |
| `added` | integer | yes |  |

## Store a phone's calendar events

`POST /apps/relay/api/calendar` · `relay.calendar-add` · writes · called by a phone key

Store the phone's new and changed calendar events, and mark the removed ones, once per device and occurrence.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `events` | array of object | yes | Up to 200 new or changed events; one that has not changed is skipped. |
| `events[].key` | string | yes | The phone's key for one occurrence: `<calendar>:<event>:<start ms>`. |
| `events[].calendar` | string | yes | The calendar's name; its id stays on the phone. |
| `events[].title` | string | yes |  |
| `events[].start` | integer | yes |  |
| `events[].end` | integer | yes |  |
| `events[].allDay` | boolean | yes |  |
| `events[].location` | string | no |  |
| `events[].notes` | string | no |  |
| `events[].url` | string | no |  |
| `events[].people` | array of object | yes |  |
| `events[].people[].name` | string | no |  |
| `events[].people[].email` | string | no |  |
| `events[].people[].organizer` | boolean | no |  |
| `removed` | array of string | yes | Up to 200 keys of events gone from the phone. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `received` | integer | yes |  |
| `changed` | integer | yes |  |
| `removed` | integer | yes |  |

## Count the photos

`GET /apps/relay/api/photos` · `relay.photos` · reads · called by a signed-in person only, not a device key

Answer how many photos your phones sent. No photo shows.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `count` | integer | yes | How many photos your space holds. |

## Delete all photos

`POST /apps/relay/api/photos/delete` · `relay.photos-delete` · writes · called by a signed-in person only, not a device key

Delete every photo your phones sent, and its time and place. Notes, recordings, health and places stay. It can't be undone.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `confirm` | string | yes | Type "delete" to confirm. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `deleted` | integer | yes | How many photos were deleted. |

## Check a device key

`GET /apps/relay/api/key` · `relay.key` · reads · called by any device key

Check the calling device key: answers the name it was made with, and no data.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `device` | string | yes | The key's device name. |

## Read the notes

`GET /apps/relay/api/timeline` · `relay.timeline` · reads · called by a signed-in person only, not a device key

Read Relay Everything's notes, newest first, with each one's place.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `before` | integer | no | Only notes recorded before this Unix time in milliseconds: the last page's `next`. |
| `beforeId` | string | no | With `before`, also the notes at that time with a lower id: the last page's `nextId`. |
| `limit` | integer | no | How many notes, 50 when left out. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `notes` | array of object | yes |  |
| `notes[].id` | string | yes |  |
| `notes[].source` | "ring" or "typed" | yes |  |
| `notes[].text` | string | yes |  |
| `notes[].recordedAt` | number | yes |  |
| `notes[].device` | string | yes |  |
| `notes[].audio` | boolean | yes |  |
| `notes[].place` | object or null | yes |  |
| `notes[].place.lat` | number | yes |  |
| `notes[].place.lon` | number | yes |  |
| `notes[].place.accuracy` | number or null | yes |  |
| `notes[].place.name` | string or null | yes |  |
| `notes[].place.from` | "phone" or "history" | yes |  |
| `notes[].attachments` | array of object | yes | The note's files, oldest first. |
| `notes[].attachments[].id` | string | yes |  |
| `notes[].attachments[].name` | string | yes |  |
| `notes[].attachments[].type` | string | yes |  |
| `notes[].attachments[].size` | number | yes |  |
| `notes[].attachments[].ready` | boolean | yes | True once the phone has sent the file: then GET attachment opens it. |
| `next` | number or null | yes |  |
| `nextId` | string or null | yes |  |

## Read one day

`GET /apps/relay/api/summary` · `relay.summary` · reads · called by a signed-in person only, not a device key

Count a day's notes, total its health samples, and list its places and calendar events.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `day` | string | yes | The day, as YYYY-MM-DD. |
| `offset` | integer | no | The viewer's time zone, in minutes east of UTC; 0 when left out. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `day` | string | yes |  |
| `notes` | number | yes |  |
| `steps` | number | yes |  |
| `sleepMinutes` | number | yes |  |
| `heartRate` | object or null | yes |  |
| `heartRate.min` | number | yes |  |
| `heartRate.max` | number | yes |  |
| `heartRate.average` | number | yes |  |
| `workouts` | object | yes |  |
| `workouts.count` | number | yes |  |
| `workouts.minutes` | number | yes |  |
| `weightKg` | number | no |  |
| `restingHeartRate` | number | no |  |
| `hrvSdnn` | number | no |  |
| `hrvRmssd` | number | no |  |
| `bloodOxygen` | object | no |  |
| `bloodOxygen.min` | number | yes |  |
| `bloodOxygen.average` | number | yes |  |
| `bloodPressure` | array of object | no |  |
| `bloodPressure[].at` | number | yes |  |
| `bloodPressure[].upper` | number | yes |  |
| `bloodPressure[].lower` | number | yes |  |
| `cycleFlow` | number | no |  |
| `mindfulMinutes` | number | no |  |
| `waterMl` | number | no |  |
| `events` | array of object | yes |  |
| `events[].title` | string | yes |  |
| `events[].start` | number | yes |  |
| `events[].end` | number | yes |  |
| `events[].allDay` | boolean | yes |  |
| `events[].people` | array of string | yes |  |
| `places` | array of object | yes |  |
| `places[].name` | string | yes |  |
| `places[].lat` | number | yes |  |
| `places[].lon` | number | yes |  |
| `places[].from` | number | yes |  |
| `places[].to` | number | yes |  |

## List the webhooks

`GET /apps/relay/api/webhooks` · `relay.webhooks` · reads · called by a signed-in person only, not a device key

List the webhooks Relay Everything sends to, each with its state, what waits, its last answer and its recent tries, and the kinds of data a webhook can take.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `webhooks` | array of object | yes |  |
| `webhooks[].id` | string | yes |  |
| `webhooks[].name` | string | yes |  |
| `webhooks[].url` | string | yes |  |
| `webhooks[].kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `webhooks[].state` | "working" or "paused" or "failing" or "backfilling" | yes | backfilling: sending past data. |
| `webhooks[].waiting` | integer | yes | How many stored items wait to be sent. |
| `webhooks[].lastStatus` | number or null | yes |  |
| `webhooks[].lastError` | string or null | yes |  |
| `webhooks[].lastSentAt` | number or null | yes |  |
| `webhooks[].nextTryAt` | number or null | yes |  |
| `webhooks[].failingSince` | number or null | yes |  |
| `webhooks[].createdAt` | number | yes |  |
| `webhooks[].attempts` | array of object | yes | The last 20 tries, newest first. |
| `webhooks[].attempts[].at` | number | yes |  |
| `webhooks[].attempts[].type` | string | yes |  |
| `webhooks[].attempts[].status` | number or null | yes |  |
| `webhooks[].attempts[].ms` | number | yes |  |
| `webhooks[].attempts[].error` | string or null | yes |  |
| `webhooks[].attempts[].first` | number or null | yes |  |
| `webhooks[].attempts[].last` | number or null | yes |  |
| `kinds` | array of object | yes |  |
| `kinds[].id` | "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `kinds[].label` | string | yes |  |
| `kinds[].detail` | string | yes |  |
| `kinds[].always` | boolean | yes |  |
| `kinds[].sensitive` | boolean | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Add a webhook

`POST /apps/relay/api/webhooks` · `relay.webhooks-add` · writes · called by a signed-in person only, not a device key

Add an address that gets each new note, and each kind of data ticked for it. The answer holds its secret, once.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `name` | string | yes | A name for the webhook, such as the database's. |
| `url` | string | yes | The https address Relay Everything sends to. |
| `kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes | What it takes besides notes, which always go: any of health, locations, calendar, photos. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `webhook` | object | yes |  |
| `webhook.id` | string | yes |  |
| `webhook.name` | string | yes |  |
| `webhook.url` | string | yes |  |
| `webhook.kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `webhook.state` | "working" or "paused" or "failing" or "backfilling" | yes | backfilling: sending past data. |
| `webhook.waiting` | integer | yes | How many stored items wait to be sent. |
| `webhook.lastStatus` | number or null | yes |  |
| `webhook.lastError` | string or null | yes |  |
| `webhook.lastSentAt` | number or null | yes |  |
| `webhook.nextTryAt` | number or null | yes |  |
| `webhook.failingSince` | number or null | yes |  |
| `webhook.createdAt` | number | yes |  |
| `webhook.attempts` | array of object | yes | The last 20 tries, newest first. |
| `webhook.attempts[].at` | number | yes |  |
| `webhook.attempts[].type` | string | yes |  |
| `webhook.attempts[].status` | number or null | yes |  |
| `webhook.attempts[].ms` | number | yes |  |
| `webhook.attempts[].error` | string or null | yes |  |
| `webhook.attempts[].first` | number or null | yes |  |
| `webhook.attempts[].last` | number or null | yes |  |
| `secret` | string | yes | Shown this once. |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Change a webhook

`POST /apps/relay/api/webhooks/update` · `relay.webhooks-update` · writes · called by a signed-in person only, not a device key

Rename a webhook, change its address or ticks, or pause and resume it. A new address or ticks clear a failure.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |
| `name` | string | no | A name for the webhook, such as the database's. |
| `url` | string | no | The https address Relay Everything sends to. |
| `kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | no | What it takes besides notes, which always go: any of health, locations, calendar, photos. |
| `active` | boolean | no | False pauses it; true sends again from where it stopped. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `webhook` | object | yes |  |
| `webhook.id` | string | yes |  |
| `webhook.name` | string | yes |  |
| `webhook.url` | string | yes |  |
| `webhook.kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `webhook.state` | "working" or "paused" or "failing" or "backfilling" | yes | backfilling: sending past data. |
| `webhook.waiting` | integer | yes | How many stored items wait to be sent. |
| `webhook.lastStatus` | number or null | yes |  |
| `webhook.lastError` | string or null | yes |  |
| `webhook.lastSentAt` | number or null | yes |  |
| `webhook.nextTryAt` | number or null | yes |  |
| `webhook.failingSince` | number or null | yes |  |
| `webhook.createdAt` | number | yes |  |
| `webhook.attempts` | array of object | yes | The last 20 tries, newest first. |
| `webhook.attempts[].at` | number | yes |  |
| `webhook.attempts[].type` | string | yes |  |
| `webhook.attempts[].status` | number or null | yes |  |
| `webhook.attempts[].ms` | number | yes |  |
| `webhook.attempts[].error` | string or null | yes |  |
| `webhook.attempts[].first` | number or null | yes |  |
| `webhook.attempts[].last` | number or null | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Remove a webhook

`POST /apps/relay/api/webhooks/remove` · `relay.webhooks-remove` · writes · called by a signed-in person only, not a device key

Stop sending to a webhook and delete its secret and its tries. Your notes stay in Relay Everything.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `removed` | boolean | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Make a new secret

`POST /apps/relay/api/webhooks/secret` · `relay.webhooks-secret` · writes · called by a signed-in person only, not a device key

Replace a webhook's secret. The old one stops working at once; the answer holds the new one, once.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `secret` | string | yes | Shown this once. |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Send a test

`POST /apps/relay/api/webhooks/test` · `relay.webhooks-test` · calls another service · called by a signed-in person only, not a device key

Send a signed webhook.test message now, and answer with what the address said. It sends no data.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `status` | number or null | yes | The address's HTTP status, or null with no answer. |
| `ms` | number | yes |  |
| `error` | string or null | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Send past data

`POST /apps/relay/api/webhooks/resend` · `relay.webhooks-resend` · writes · called by a signed-in person only, not a device key

Send again everything the webhook takes that was recorded since a time, in the order Relay Everything stored it, then carry on.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |
| `since` | integer | yes | From this Unix time in milliseconds. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `webhook` | object | yes |  |
| `webhook.id` | string | yes |  |
| `webhook.name` | string | yes |  |
| `webhook.url` | string | yes |  |
| `webhook.kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `webhook.state` | "working" or "paused" or "failing" or "backfilling" | yes | backfilling: sending past data. |
| `webhook.waiting` | integer | yes | How many stored items wait to be sent. |
| `webhook.lastStatus` | number or null | yes |  |
| `webhook.lastError` | string or null | yes |  |
| `webhook.lastSentAt` | number or null | yes |  |
| `webhook.nextTryAt` | number or null | yes |  |
| `webhook.failingSince` | number or null | yes |  |
| `webhook.createdAt` | number | yes |  |
| `webhook.attempts` | array of object | yes | The last 20 tries, newest first. |
| `webhook.attempts[].at` | number | yes |  |
| `webhook.attempts[].type` | string | yes |  |
| `webhook.attempts[].status` | number or null | yes |  |
| `webhook.attempts[].ms` | number | yes |  |
| `webhook.attempts[].error` | string or null | yes |  |
| `webhook.attempts[].first` | number or null | yes |  |
| `webhook.attempts[].last` | number or null | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Try again now

`POST /apps/relay/api/webhooks/retry` · `relay.webhooks-retry` · writes · called by a signed-in person only, not a device key

Clear a webhook's failure and send everything waiting, in order, from where it stopped.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The webhook's id. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `webhook` | object | yes |  |
| `webhook.id` | string | yes |  |
| `webhook.name` | string | yes |  |
| `webhook.url` | string | yes |  |
| `webhook.kinds` | array of "notes" or "health" or "locations" or "calendar" or "photos" | yes |  |
| `webhook.state` | "working" or "paused" or "failing" or "backfilling" | yes | backfilling: sending past data. |
| `webhook.waiting` | integer | yes | How many stored items wait to be sent. |
| `webhook.lastStatus` | number or null | yes |  |
| `webhook.lastError` | string or null | yes |  |
| `webhook.lastSentAt` | number or null | yes |  |
| `webhook.nextTryAt` | number or null | yes |  |
| `webhook.failingSince` | number or null | yes |  |
| `webhook.createdAt` | number | yes |  |
| `webhook.attempts` | array of object | yes | The last 20 tries, newest first. |
| `webhook.attempts[].at` | number | yes |  |
| `webhook.attempts[].type` | string | yes |  |
| `webhook.attempts[].status` | number or null | yes |  |
| `webhook.attempts[].ms` | number | yes |  |
| `webhook.attempts[].error` | string or null | yes |  |
| `webhook.attempts[].first` | number or null | yes |  |
| `webhook.attempts[].last` | number or null | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## Run the sweep (previews only)

`POST /apps/relay/api/webhooks/sweep` · `relay.webhooks-sweep` · writes · called by a signed-in person only, not a device key

Run what your space's alarm runs every 15 minutes: send each of your webhooks left behind, and drop tries older than 30 days.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `woken` | integer | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No webhook has this id. |
| `address_invalid` | That is not a web address. |
| `address_not_https` | The address must start with https://. |
| `address_has_login` | The address can't hold a user name or password. |
| `address_private` | The address can't be this computer or a private network. |
| `address_own_site` | The address can't be Relay Everything's own site. |

## List connected AI apps

`GET /apps/relay/api/ai-apps` · `relay.ai-apps` · reads · called by a signed-in person only, not a device key

List the AI chat apps you connected to Relay Everything's AI connector, with the address to connect another.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `address` | string | yes |  |
| `apps` | array of object | yes |  |
| `apps[].id` | string | yes |  |
| `apps[].name` | string | yes |  |
| `apps[].connectedAt` | number | yes |  |

### Errors

| Code | When |
|---|---|
| `unavailable` | The AI connector is not set up here. |
| `not_found` | You have no connected AI app with this id. |

## Disconnect an AI app

`POST /apps/relay/api/ai-apps-disconnect` · `relay.ai-app-disconnect` · writes · called by a signed-in person only, not a device key

End one of your AI apps' connection to Relay Everything: its sign-in stops working at once.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The connection's id, from the list of connected AI apps. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |

### Errors

| Code | When |
|---|---|
| `unavailable` | The AI connector is not set up here. |
| `not_found` | You have no connected AI app with this id. |

## List what you connected, by name

`GET /apps/relay/api/connections` · `relay.connections` · reads · called by a signed-in person or a phone key

The names of your connected AI apps and of your webhooks, for the phone's Home. It holds no address, secret or send state. Where the AI connector is not set up, the AI apps list is empty.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `aiApps` | array of object | yes | Each connected AI app. |
| `aiApps[].name` | string | yes |  |
| `webhooks` | array of object | yes | Each webhook, paused ones too. |
| `webhooks[].name` | string | yes |  |

## Save the AI's summary of a chat

`POST /apps/relay/api/chat-saves` · `relay.chat-saves-add` · writes · called by a Claude Code chat key only

Store a title and a summary the AI wrote for a chat this key sent. The chat's messages stay as they are; the newest save's title shows as the chat's title.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `sessionId` | string | yes | Claude Code's id for the chat. |
| `title` | string | yes | The AI's title for the chat. |
| `text` | string | yes | The AI's summary, shown as written by the AI. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `ok` | boolean | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | This key has sent no chat with that session id. Send the chat first. |

## List the chats

`GET /apps/relay/api/chats` · `relay.chats` · reads · called by a signed-in person only, not a device key

List the saved Claude Code chats, newest first, or only those whose messages or AI summaries hold every word of `q`.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `q` | string | no | Words to find, in any case. |
| `before` | integer | no | Only chats last active before this Unix time in milliseconds: the last page's `next`. |
| `beforeId` | string | no | With `before`, also the chats at that time with a lower id: the last page's `nextId`. |
| `limit` | integer | no | How many chats, 30 when left out. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `chats` | array of object | yes |  |
| `chats[].id` | string | yes |  |
| `chats[].title` | string | yes |  |
| `chats[].project` | string | yes |  |
| `chats[].app` | string | yes |  |
| `chats[].startedAt` | number | yes |  |
| `chats[].lastAt` | number | yes |  |
| `chats[].messages` | number | yes | How many messages the chat holds. |
| `chats[].savedByAi` | boolean | yes | True when the AI saved a title and summary for it. |
| `next` | number or null | yes |  |
| `nextId` | string or null | yes |  |

## Read one chat

`GET /apps/relay/api/chat` · `relay.chat` · reads · called by a signed-in person only, not a device key

Read one chat: its AI saves, newest first, and its messages in order, a part at a time.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The chat's id, from the list of chats. |
| `after` | integer | no | Only messages after this one: the last part's `next`. |
| `limit` | integer | no | How many messages, 200 when left out. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `chat` | object | yes |  |
| `chat.id` | string | yes |  |
| `chat.title` | string | yes |  |
| `chat.project` | string | yes |  |
| `chat.app` | string | yes |  |
| `chat.startedAt` | number | yes |  |
| `chat.lastAt` | number | yes |  |
| `chat.messages` | number | yes | How many messages the chat holds. |
| `chat.savedByAi` | boolean | yes | True when the AI saved a title and summary for it. |
| `saves` | array of object | yes |  |
| `saves[].id` | string | yes |  |
| `saves[].title` | string | yes |  |
| `saves[].text` | string | yes | The summary, written by the AI. |
| `saves[].createdAt` | number | yes |  |
| `messages` | array of object | yes |  |
| `messages[].seq` | number | yes |  |
| `messages[].role` | "you" or "ai" or "step" | yes | Yours, the AI's, or one step the AI took. |
| `messages[].text` | string | yes |  |
| `messages[].at` | number | yes |  |
| `next` | number or null | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No chat has this id. |

## Delete a chat

`DELETE /apps/relay/api/chat` · `relay.chat-delete` · writes · called by a signed-in person only, not a device key

Delete one chat with its messages and AI saves. It can't be brought back.

### Input

Send the input as query parameters.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The chat's id, from the list of chats. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | No chat has this id. |

## List the devices

`GET /apps/relay/api/devices` · `relay.devices` · reads · called by a signed-in person only, not a device key

List your devices and their keys' state, newest last. No key shows.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `devices` | array of object | yes |  |
| `devices[].id` | string | yes |  |
| `devices[].name` | string | yes |  |
| `devices[].reaches` | "phone" or "chats" or "api" | yes | phone: notes, files, health, places and photos, from a phone. chats: Claude Code chats. api: the web API, which reads and adds notes. |
| `devices[].createdAt` | number | yes |  |
| `devices[].revokedAt` | number or null | yes |  |

## Add a device

`POST /apps/relay/api/devices` · `relay.devices-add` · writes · called by a signed-in person only, not a device key

Make a key for a new device. The answer holds the key and its QR code text: both show only this once. An API key's answer names the web API's address.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `name` | string | yes | A name you know the device by. |
| `reaches` | "phone" or "chats" or "api" | yes | phone: notes, files, health, places and photos, from a phone. chats: Claude Code chats. api: the web API, which reads and adds notes. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |
| `name` | string | yes |  |
| `reaches` | "phone" or "chats" or "api" | yes | phone: notes, files, health, places and photos, from a phone. chats: Claude Code chats. api: the web API, which reads and adds notes. |
| `key` | string | yes | Shown this once. |
| `qr` | string | yes | What the phone scans: the server's address and the key. |
| `api` | string or null | yes | An API key's web API address, or null when this server has no AI connector. |

## Turn off a device

`POST /apps/relay/api/devices/off` · `relay.devices-off` · writes · called by a signed-in person only, not a device key

Turn off a device's key: it stops at once. The device's notes stay.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes | The device's id, from the list of devices. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |
| `revokedAt` | number | yes |  |

### Errors

| Code | When |
|---|---|
| `not_found` | You have no device with this id. |

## Read your notes addresses

`GET /apps/relay/api/inbox` · `relay.inbox` · reads · called by a signed-in person only, not a device key

Answer your secret notes address, made on first read, and the shared address for your sign-in email.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `email` | object | yes | Email notes: whether this server takes email, and your addresses. |
| `email.on` | boolean | yes | True when this server takes email: its owner set a mail domain. |
| `email.address` | string or null | yes | Your secret notes address: any mail to it becomes a note. Null when email is off. |
| `email.shared` | string or null | yes | The shared address: mail to it from your sign-in email becomes a note. Null when email is off. |

## Make a new notes address

`POST /apps/relay/api/inbox/address` · `relay.inbox-address` · writes · called by a signed-in person only, not a device key

Replace your secret notes address with a new one. Mail to the old address makes no note from now on.

### Input

Send the input as a JSON body.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `email` | object | yes | Email notes: whether this server takes email, and your addresses. |
| `email.on` | boolean | yes | True when this server takes email: its owner set a mail domain. |
| `email.address` | string or null | yes | Your secret notes address: any mail to it becomes a note. Null when email is off. |
| `email.shared` | string or null | yes | The shared address: mail to it from your sign-in email becomes a note. Null when email is off. |

## Run the kept mail's sweep (previews only)

`POST /apps/relay/api/inbox/sweep` · `relay.inbox-sweep` · writes · called by a signed-in person only, not a device key

Run what the server runs each day: delete mail kept for emails with no account that is older than 30 days.

### Input

Send the input as a JSON body.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `deleted` | integer | yes | How many kept messages it deleted. |

## Read the account

`GET /apps/relay/api/account` · `relay.account` · reads · called by a signed-in person only, not a device key

Answer the signed-in person's email.

### Input

It takes no input.

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `email` | string | yes |  |

## Delete my account

`POST /apps/relay/api/account-delete` · `relay.account-delete` · writes · called by a signed-in person only, not a device key

Delete your account: your notes, recordings, photos, health, places, chats, devices, webhooks and AI apps. It can't be undone.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `email` | string | yes | Your account's email, typed to confirm. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `deleted` | boolean | yes |  |

### Errors

| Code | When |
|---|---|
| `invalid_input` | Type your account's email to confirm. |

## Routes with their own page

- `POST /apps/relay/api/attachments`: [Send a note's file, after its note](../files/#send-a-file)
- `POST /apps/relay/api/photos`: [Send a photo from the phone, with a phone key](../../app/photos/#what-the-phone-sends)
- `GET /apps/relay/api/audio`: [Play a note's recording](../recordings/)
- `GET /apps/relay/api/attachment`: [Open a note's file](../files/#open-a-file)
- `POST /apps/relay/api/chats`: [Send a Claude Code chat's new messages, with a chat key](../../connections/claude-code/#what-the-server-receives)
