---
title: Routes
description: Every route of the Relay server, with its fields, made from the server's own route list.
---

<!-- Made by `npm run relay:api-doc` in app/ from app/worker/apps/relay/. Do not edit it by hand. -->

Each route sits under `https://<your-relay-server>/apps/relay/api/`. Send your key's two headers with each call, as
[Keys](../keys/) shows. A refused call answers `{ "error": { "code": "...", "message": "..." } }`; [Keys](../keys/#errors)
lists the codes.

## Store a typed note

`POST /apps/relay/api/notes` · `relay.notes-add` · writes · called by a device key or a signed-in person

Store a note typed on a Relay phone, once per phone and clientId.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `clientId` | string | yes | The phone's own id for the note, so a resend is stored once. |
| `text` | string | yes | What the note says. |
| `createdAt` | integer | yes | When it was written, in Unix milliseconds. |
| `lat` | number | no | Where it was written: latitude. Send it with lon. |
| `lon` | number | no | Where it was written: longitude. Send it with lat. |
| `accuracy` | number | no | How sure the phone was of the place, in meters. |
| `place` | string | no | The place's name from the phone's address lookup. |

### Output

| Field | Type | Required | What it holds |
|---|---|---|---|
| `id` | string | yes |  |
| `added` | boolean | yes |  |

## Store a phone's samples

`POST /apps/relay/api/health` · `relay.samples-add` · writes · called by a device key or a signed-in person

Store steps, heart rate, sleep and workouts from Apple Health or Health Connect, once per type, time span and source.

### Input

Send the input as a JSON body.

| Field | Type | Required | What it holds |
|---|---|---|---|
| `samples` | array of object | yes | Up to 500 rows; a row stored before is skipped. |
| `samples[].type` | "steps" or "heart_rate" or "sleep" or "workout" | yes |  |
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

`POST /apps/relay/api/locations` · `relay.points-add` · writes · called by a device key or a signed-in person

Store the phone's location history, once per time, and give ring notes near those times their place.

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

## Read the notes

`GET /apps/relay/api/timeline` · `relay.timeline` · reads · called by a device key or a signed-in person

Read Relay's notes, newest first, with each one's place.

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
| `next` | number or null | yes |  |
| `nextId` | string or null | yes |  |

## Read one day

`GET /apps/relay/api/summary` · `relay.summary` · reads · called by a signed-in person only, not a device key

Count a day's notes, total its health samples and list its places.

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
| `places` | array of object | yes |  |
| `places[].name` | string | yes |  |
| `places[].lat` | number | yes |  |
| `places[].lon` | number | yes |  |
| `places[].from` | number | yes |  |
| `places[].to` | number | yes |  |

## List connected AI apps

`GET /apps/relay/api/ai-apps` · `relay.ai-apps` · reads · called by a signed-in person only, not a device key

List the AI chat apps connected to Relay's AI connector, with the address to connect another.

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

## Disconnect an AI app

`POST /apps/relay/api/ai-apps-disconnect` · `relay.ai-app-disconnect` · writes · called by a signed-in person only, not a device key

End one AI app's connection to Relay: its sign-in stops working at once.

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

## Routes with their own page

- `POST /apps/relay/api/pebble`: [Take a ring note from the Pebble app](../pebble-webhook/)
- `GET /apps/relay/api/audio`: [Play a note's recording](../recordings/)
- `POST /apps/relay/api/chats`: [Send a Claude Code chat's new messages, with a chat key](../../connections/claude-code/#what-the-server-receives)
