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

With `q`, the notes whose text holds every word, as the `search` tool; with `tag`, the notes on that topic and its parts: `source` picks older recorded or typed notes, and `limit` is at most 50. Without `q` or `tag`, every note from `from` to `to`, as the `timeline` tool: both are needed, and `limit` is at most 100. Newest first; read on with `cursor`.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | no | The words to find. |
| `tag` | query | string | no | A topic, such as battery or bike/charging: it finds its parts too, so bike finds bike/charging. |
| `from` | query | string | no | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | no | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `source` | query | "ring" or "typed" | no | Only older recorded notes, or only typed ones. |
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

Read one note by its id, with the places you stayed within 30 minutes of it and the health totals of its day.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The note's id, from search or timeline. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Sum up a day

`GET /v1/days/{day}` · `getDay`

One day: how many notes, steps, sleep minutes, heart rate, workouts, the other health values it has, the nights or naps that ended that day with their stage minutes, each workout with its kind, km and calories, each stay with its name and times, each trip with its mode, km and minutes, and the calendar's events with the people in each. Each stay and trip from the phone has an `id`: give it to points for its route.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `day` | path | string | yes | The day, as YYYY-MM-DD. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read health over time

`GET /v1/health` · `getHealth`

One value per hour or day for one kind of health data: steps, sleep, mindful minutes and water (ml) as `total`; heart rate and blood pressure (mmHg) as min, max and average; workouts as a count and minutes; weight (kg) as `latest`; resting heart rate, heart rate variability (ms; hrv_sdnn from iPhone, hrv_rmssd from Android) as `average`; blood oxygen (%) as min and average; cycle flow as the highest `flow`, 0 none to 3 heavy. Sleep counts on the day it ends.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `type` | query | "steps" or "heart_rate" or "sleep" or "workout" or "weight" or "resting_heart_rate" or "hrv_sdnn" or "hrv_rmssd" or "blood_oxygen" or "blood_pressure_systolic" or "blood_pressure_diastolic" or "cycle_flow" or "mindful" or "water" | yes | Which health data. |
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `bucket` | query | "hour" or "day" | no | One value per hour or per day, at most 400. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read nights of sleep

`GET /v1/nights` · `listNights`

The nights, and naps, that end from one time to another, newest first: when the person went to bed, fell asleep and woke, and the minutes asleep, in core (light), deep and REM sleep, and awake. Of nights that overlap, as from a watch and the phone's bedtime, the one with the most sleep. Give `stages` to add each night's stage timeline, such as to see when deep sleep came.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `stages` | query | boolean | no | Add each night's stage timeline, in time order. |
| `limit` | query | integer | no | How many nights, at most 100. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read workouts

`GET /v1/workouts` · `listWorkouts`

The workouts that start from one time to another, newest first, each with its kind (such as running or traditional_strength_training), minutes, km and calories when the phone has them. A workout from before the phone sent its kind has `kind` null. Calories are active calories from an iPhone and total calories from Android.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `limit` | query | integer | no | How many workouts, at most 100. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read places visited

`GET /v1/places` · `listPlaces`

The stays and trips from one time to another, oldest first: each stay's name, street, where it is, and when you arrived and left; each trip's mode (walking, running, cycling, driving, flying or unknown), km, minutes, and the stays it went between. Each stay and trip from the phone has an `id`: give it to points for its route.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `limit` | query | integer | no | How many stays, at most 200. Read on from `next`. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read location points

`GET /v1/points` · `listPoints`

The location points of one stay or trip, by its `id` from places or day_summary, from the phone that made it; or every phone's points from `from` to `to`, at most 7 days. Each point has its time, lat, lon, accuracy (m) and street. Oldest first, at most 500, spread evenly with the first and the last; `total` says how many there were. No points means the person keeps only stays and trips, or the phone sent none: do not ask again.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | query | integer | no | The id of a stay or trip, from places or day_summary. |
| `from` | query | string | no | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | no | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Read calendar events

`GET /v1/calendar` · `listEvents`

The events from the phone's calendars that overlap one time to another, with each one's calendar, title, time, place, notes and people. With `q`, only events whose title, place, notes or people hold every word, newest first; without, in start order.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `from` | query | string | yes | The first time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | yes | The time to stop before: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `q` | query | string | no | The words to find. |
| `limit` | query | integer | no | How many events, at most 100. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Search saved chats

`GET /v1/chats` · `searchChats`

Find saved AI chats from Claude Code and Codex whose messages or AI summaries hold every word of the query, newest first, with up to 3 matching lines each.

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

## Change a note's topics

`POST /v1/notes/{id}/tags` · `tagNote`

Add and remove a note's topics, as this computer: the note's words stay as the person wrote them. Only a computer's key; it answers the note's topics.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The note's id. |
| `add` | body | array | no | Topics to add. |
| `remove` | body | array | no | Topics to remove. |

## Search the memory

`GET /v1/memory` · `searchMemory`

The memory's facts, newest first, as the `memory` tool: `q` finds every word in the text columns, `tag` a topic and its parts, `source` the facts from one record, such as relay:chat/<id>, and any column its value as its own field, such as `kind=decision`. Only live facts, unless `all=true`. The answer lists the memory's columns.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `q` | query | string | no | The words to find. |
| `tag` | query | string | no | A topic, such as battery or bike/charging: it finds its parts too, so bike finds bike/charging. |
| `source` | query | string | no | A record's link, such as relay:chat/<id> or relay:note/<id>: it finds its messages too. |
| `from` | query | string | no | Only facts added from this time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `to` | query | string | no | Only facts added before this time: a day (2026-11-04), a time in the zone (2026-11-04T09:00), or a time with its offset. |
| `all` | query | boolean | no | Add the facts that were replaced. |
| `where` | query | object | no | A value for each of the person's columns, such as { "kind": "decision" }. In the web API, send each as its own field. |
| `limit` | query | integer | no | How many facts, at most 50. |
| `cursor` | query | string | no | The last answer's `nextCursor`, to read the next page. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Add facts

`POST /v1/memory` · `addFacts`

Add up to 50 facts to the memory, all or none, as this computer. Each fact needs a tag, a source and every required column, and each value must fit its column's type. A fact can't be changed or deleted: name the facts it replaces instead. Send the same `clientId` again after a lost answer, and the fact is stored once. Only a computer's key adds. 201 when any was added.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `facts` | body | array | yes | The facts to add. |

## Read the memory's columns

`GET /v1/memory/columns` · `getColumns`

The memory's live columns, each with its type, whether it is required, and its note; the removed ones; and, with `changes`, each column change with its device and time.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `changes` | query | boolean | no | Add the last 100 column changes. |

## Change the memory's columns

`POST /v1/memory/columns` · `changeColumns`

Add, change and remove the memory's columns, all or none, at most 20 live. A column's type never changes; a removed column's values stay in the facts that have them. Only a computer's key changes columns. It answers the columns.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `add` | body | array | no | Columns to add. |
| `change` | body | array | no | Columns whose note or `required` changes. |
| `remove` | body | array | no | Columns to remove. |

## Read one fact

`GET /v1/memory/{id}` · `getFact`

Read one fact of the memory by its id, with the facts it replaced and the fact that replaced it.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The fact's id, such as fk3x9. |
| `timezone` | query | string | no | An IANA time zone, such as Europe/London, for days and the times in the answer; America/Toronto when left out. |

## Change a fact's topics

`POST /v1/memory/{id}/tags` · `tagFact`

Add and remove a fact's topics, as this computer: its words and sources stay as they are, and it keeps at least one topic. Only a computer's key; it answers the fact's topics.

| Field | In | Type | Required | What it holds |
|---|---|---|---|---|
| `id` | path | string | yes | The fact's id, such as fk3x9. |
| `add` | body | array | no | Topics to add. |
| `remove` | body | array | no | Topics to remove. |

## Open the knowledge web

`POST /v1/knowledge/access` · `openKnowledge`

A pass to the person's knowledge web, a git repository of topic pages, for at most one hour: its git address, the pass to send as `Authorization: Bearer`, and when it ends. The first ask makes the web. Only a computer's key gets one. A server whose Cloudflare account has no Artifacts answers 501 `not_set_up`.

It takes no input.

## Check the caller

`GET /v1/me` · `getMe`

The caller's device name, as the phone's key check answers, and whether it may add notes. It reads no data.

It takes no input.
