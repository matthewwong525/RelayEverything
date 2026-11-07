---
title: Web API reference
description: Every route of the Relay Everything web API, with its fields, made from its OpenAPI file.
---

<!-- Made by `npm run relay:api-doc` in app/ from app/worker/relay-mcp/. Do not edit it by hand. -->

Each route sits under `https://<your-relay-server>/v1/`, on your AI connector's address. Send a connected app's token or an
API key as `Authorization: Bearer …`, as [Connect a service](../connect-a-service/) shows. The answers' fields are in the
[OpenAPI file](/api/v1.openapi.json). A refused call answers `{ "error": "...", "error_description": "..." }`.

## Search notes, or read a time range

`GET /v1/notes` · `listNotes`

With `q`, the notes whose text holds every word, as the `search` tool: `source` picks ring or typed notes, and `limit` is at most 50. Without `q`, every note from `from` to `to`, as the `timeline` tool: both are needed, and `limit` is at most 100. Newest first; read on with `cursor`.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | no | The words to find. |
| `from` | query | string | no | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | no | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `source` | query | "ring" or "typed" | no | Only ring notes, or only typed ones. |
| `limit` | query | integer | no | How many notes, at most 100. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Add a note

`POST /v1/notes` · `addNote`

Add a typed note, with this key's or app's name as its device, and send it on to the person's webhooks. Send the same `clientId` again after a lost answer: the note is stored once, and `added` is false. 201 when added.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `clientId` | body | string | yes | Your own id for this note, 8 to 64 letters, digits or dashes, such as a new UUID, so a resend is stored once. |
| `text` | body | string | yes | What the note says. |
| `createdAt` | body | string | no | When it was written; now when left out: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `lat` | body | number | no | Where it was written: latitude. Send it with lon. |
| `lon` | body | number | no | Where it was written: longitude. Send it with lat. |
| `accuracy` | body | number | no | How sure you are of the place, in meters. |
| `place` | body | string | no | The place's name, such as a street. |
| `timezone` | body | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read one note

`GET /v1/notes/{id}` · `getNote`

Read one note by its id, with the places visited within 30 minutes of it and the health totals of its day.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The note's id, from search or timeline. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Sum up a day

`GET /v1/days/{day}` · `getDay`

One day: how many notes, steps, sleep minutes, heart rate, workouts, and each place visited.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `day` | path | string | yes | The day, as YYYY-MM-DD. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read health over time

`GET /v1/health` · `getHealth`

One value per hour or day for one kind of health data: steps and sleep minutes as `total`, heart rate as min, max and average, workouts as a count and minutes. Sleep counts on the day it ends.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `type` | query | "steps" or "heart_rate" or "sleep" or "workout" | yes | Which health data. |
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `bucket` | query | "hour" or "day" | no | One value per hour or per day, at most 400. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read places visited

`GET /v1/places` · `listPlaces`

The places visited from one time to another, oldest first: each place's name, where it is, and when you arrived and left.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `limit` | query | integer | no | How many visits, at most 200. Read on from `next`. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Search saved chats

`GET /v1/chats` · `searchChats`

Find saved Claude Code chats whose messages or AI summaries hold every word of the query, newest first, with up to 3 matching lines each.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | yes | The words to find. |
| `from` | query | string | no | Only chats active from this time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | no | Only chats last active before this time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `limit` | query | integer | no | How many chats, at most 20. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read one saved chat

`GET /v1/chats/{id}` · `getChat`

Read one saved chat by its id: the AI's saved summaries, then its messages in order, 200 at a time. Each message is yours (`you`), the AI's (`ai`), or one line for a step the AI took (`step`).

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The chat's id, from search_chats. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next part. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Check the caller

`GET /v1/me` · `getMe`

The caller's device name, as the phone's key check answers, and whether it may add notes. It reads no data.

It takes no input.

## Read from Google

`GET /v1/google/{service}/{path}` · `googleGet`

GET to the person's own Gmail, Calendar, Drive or Contacts, with their sign-in; Google's status, type and body come back as Google sent them. Contacts take GET only. Nothing deletes an email, a thread, a draft or a Drive file for ever: put it in the bin. An API key or an app connected after Google reaches it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `service` | path | "gmail" or "calendar" or "drive" or "contacts" | yes | gmail, calendar, drive (with upload/ for an upload) or contacts. |
| `path` | path | string | yes | Google's own path after the service's base: Gmail's after users/me/, Calendar's after calendar/v3/, Drive's after drive/v3/, People's after v1/. Send it as is, not encoded: its slashes stay slashes, and an encoded slash (%2F) is refused. Google's query goes as this request's own query string, not in `path`. A client that encodes path fields can use the fixed example routes, such as /v1/google/gmail/messages. |

## Send to Google

`POST /v1/google/{service}/{path}` · `googlePost`

POST to the person's own Gmail, Calendar, Drive or Contacts, with their sign-in; Google's status, type and body come back as Google sent them. Contacts take GET only. Nothing deletes an email, a thread, a draft or a Drive file for ever: put it in the bin. An API key or an app connected after Google reaches it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `service` | path | "gmail" or "calendar" or "drive" or "contacts" | yes | gmail, calendar, drive (with upload/ for an upload) or contacts. |
| `path` | path | string | yes | Google's own path after the service's base: Gmail's after users/me/, Calendar's after calendar/v3/, Drive's after drive/v3/, People's after v1/. Send it as is, not encoded: its slashes stay slashes, and an encoded slash (%2F) is refused. Google's query goes as this request's own query string, not in `path`. A client that encodes path fields can use the fixed example routes, such as /v1/google/gmail/messages. |

## Replace in Google

`PUT /v1/google/{service}/{path}` · `googlePut`

PUT to the person's own Gmail, Calendar, Drive or Contacts, with their sign-in; Google's status, type and body come back as Google sent them. Contacts take GET only. Nothing deletes an email, a thread, a draft or a Drive file for ever: put it in the bin. An API key or an app connected after Google reaches it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `service` | path | "gmail" or "calendar" or "drive" or "contacts" | yes | gmail, calendar, drive (with upload/ for an upload) or contacts. |
| `path` | path | string | yes | Google's own path after the service's base: Gmail's after users/me/, Calendar's after calendar/v3/, Drive's after drive/v3/, People's after v1/. Send it as is, not encoded: its slashes stay slashes, and an encoded slash (%2F) is refused. Google's query goes as this request's own query string, not in `path`. A client that encodes path fields can use the fixed example routes, such as /v1/google/gmail/messages. |

## Change in Google

`PATCH /v1/google/{service}/{path}` · `googlePatch`

PATCH to the person's own Gmail, Calendar, Drive or Contacts, with their sign-in; Google's status, type and body come back as Google sent them. Contacts take GET only. Nothing deletes an email, a thread, a draft or a Drive file for ever: put it in the bin. An API key or an app connected after Google reaches it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `service` | path | "gmail" or "calendar" or "drive" or "contacts" | yes | gmail, calendar, drive (with upload/ for an upload) or contacts. |
| `path` | path | string | yes | Google's own path after the service's base: Gmail's after users/me/, Calendar's after calendar/v3/, Drive's after drive/v3/, People's after v1/. Send it as is, not encoded: its slashes stay slashes, and an encoded slash (%2F) is refused. Google's query goes as this request's own query string, not in `path`. A client that encodes path fields can use the fixed example routes, such as /v1/google/gmail/messages. |

## Delete in Google

`DELETE /v1/google/{service}/{path}` · `googleDelete`

DELETE to the person's own Gmail, Calendar, Drive or Contacts, with their sign-in; Google's status, type and body come back as Google sent them. Contacts take GET only. Nothing deletes an email, a thread, a draft or a Drive file for ever: put it in the bin. An API key or an app connected after Google reaches it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `service` | path | "gmail" or "calendar" or "drive" or "contacts" | yes | gmail, calendar, drive (with upload/ for an upload) or contacts. |
| `path` | path | string | yes | Google's own path after the service's base: Gmail's after users/me/, Calendar's after calendar/v3/, Drive's after drive/v3/, People's after v1/. Send it as is, not encoded: its slashes stay slashes, and an encoded slash (%2F) is refused. Google's query goes as this request's own query string, not in `path`. A client that encodes path fields can use the fixed example routes, such as /v1/google/gmail/messages. |

## Search Gmail

`GET /v1/google/gmail/messages` · `googleGmailListMessages`

Gmail's messages.list: the ids of the emails that match a Gmail search, newest first.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | no | A Gmail search, as in Gmail's search box. |
| `maxResults` | query | integer | no | How many, at most. |
| `pageToken` | query | string | no | The last answer's `nextPageToken`, to read the next page. |

## Send an email

`POST /v1/google/gmail/messages/send` · `googleGmailSendMessage`

Gmail's messages.send: sends an email from the person's own address. A sent email can't be undone.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `raw` | body | string | yes | The whole email, as RFC 2822 text in base64url. |
| `threadId` | body | string | no | The thread a reply goes in. |

## List calendar events

`GET /v1/google/calendar/calendars/primary/events` · `googleCalendarListEvents`

Calendar's events.list on the person's own calendar.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `timeMin` | query | string | no | The first time, as RFC 3339. |
| `timeMax` | query | string | no | The time to stop before, as RFC 3339. |
| `singleEvents` | query | boolean | no | true gives each repeat on its own. |
| `pageToken` | query | string | no | The last answer's `nextPageToken`, to read the next page. |

## Add a calendar event

`POST /v1/google/calendar/calendars/primary/events` · `googleCalendarAddEvent`

Calendar's events.insert on the person's own calendar.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `sendUpdates` | query | "all" or "externalOnly" or "none" | no | Who gets Google's invitation email. |

## Search Drive files

`GET /v1/google/drive/files` · `googleDriveListFiles`

Drive's files.list: the person's files that match a Drive search.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | no | A Drive search, such as name contains 'lease'. |
| `pageSize` | query | integer | no | How many, at most. |
| `fields` | query | string | no | The fields each answer gives, such as files(id, name, mimeType). |
| `pageToken` | query | string | no | The last answer's `nextPageToken`, to read the next page. |

## Search contacts

`GET /v1/google/contacts/people:searchContacts` · `googleContactsSearch`

People's people.searchContacts: the person's saved contacts that match a name, an email address or a phone number.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `query` | query | string | yes | A name, an email address or a phone number, or the start of one. |
| `readMask` | query | string | yes | The fields to give, such as names,emailAddresses,phoneNumbers. |
| `pageSize` | query | integer | no | How many, at most. |
