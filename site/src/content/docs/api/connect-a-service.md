---
title: Connect a service
description: Let your own script or service read your Relay Everything notes, health, sleep, workouts, calendar, places and chats, and add notes, through the web API with an API key or your own sign-in.
---

The web API lets your own script or service read your Relay Everything data and add notes. It answers the same questions as the [AI connector](../../connections/connect-your-ai/), as plain HTTP with JSON. It reads, and it adds notes. A connected computer's key also adds facts to your memory and changes topics: [Memory and knowledge web](../knowledge-web/). It can't delete anything in your space. A computer's key also runs its own commands in [your agents' database](../agents-database/).

The web API is on your AI connector's address, under `/v1/`. When the connector is at `https://mcp.relayeverything.com`, the API is at `https://mcp.relayeverything.com/v1/`. Your own server's connector works the same way: `https://<your-relay-server>/v1/`. The **AI apps** page of Settings, on your Relay Everything page, shows the connector's address.

Each caller reaches only the space of the person who made its key or connected it. There are two ways in.

## With an API key

An API key is for a script or a service that runs on its own, such as a backup job.

1. On your Relay Everything page, open **Settings**, then **Devices**. Click **Add a device** and pick **API key**.
2. Give it a name you know it by, then click **Make the key**. The page shows the key once, with a `curl` example.
3. Keep the key in your script's secret store. Never put it in a file you share.

Send the key in the `Authorization` header on each call:

```sh
curl https://<your-relay-server>/v1/me \
  -H "Authorization: Bearer rek_…"
```

`GET /v1/me` answers the key's name and whether it may add notes. It reads no data, so it is a safe first call.

An API key works only on the web API. On the Relay Everything server it reaches only `GET key`. A computer's key from the [Relay Everything plugin](../../connections/claude-code/) opens the web API too. A phone's key or an older chat key can't: make an API key for it. To stop a key, click **Turn off** beside it in your list of devices. [Keys](../keys/) tells more.

## With your own sign-in

An app that has its own users signs each person in with OAuth, as the Claude app does.

1. Register the app at `https://<your-relay-server>/register` (OAuth dynamic client registration).
2. Send the person to `/authorize` with PKCE (S256). They click **Connect**, then sign in to Relay Everything.
3. Trade the code at `/token` for an access token and a refresh token.

Leave out `resource`, or send the connector's address, such as `https://<your-relay-server>`, as it. The same token then works on `/`, `/mcp` and `/v1/`. An access token lasts one hour; refresh it at `/token`. The app shows on the person's **AI apps** page in Settings, and **Disconnect** stops it at once. An app connected before the API could add notes only reads: connect it again to add.

The [OpenAPI file](/api/v1.openapi.json) names each step's address. Load it into Swagger, Postman or a code generator to make a client.

## Read

```sh
curl "https://<your-relay-server>/v1/notes?q=milk&limit=5" \
  -H "Authorization: Bearer rek_…"
```

- `GET /v1/notes?q=…`: notes that hold every word, newest first. Without `q`, give `from` and `to` for every note in that time.
- `GET /v1/notes/{id}`: one note, the places near it in time, and its day's health totals.
- `GET /v1/days/{day}`: one day's notes count, health totals, nights, workouts, places and events.
- `GET /v1/health?type=steps&from=…&to=…`: health values, one per hour or per day. `type` is any type in [Health](../../app/health/#what-it-reads), such as `weight` or `blood_pressure_systolic`.
- `GET /v1/nights?from=…&to=…`: each night of sleep, newest first, with its stage minutes. Add `stages=true` for each night's stage timeline.
- `GET /v1/workouts?from=…&to=…`: each workout, newest first, with its kind, minutes, km and calories.
- `GET /v1/places?from=…&to=…`: each stay at a place, and each trip, each with its `id`.
- `GET /v1/points?id=…`: the points of one stay or trip, at most 500. Or give `from` and `to`, up to 7 days, for every phone's points in that time.
- `GET /v1/calendar?from=…&to=…`: calendar events by start, with title, times, place, notes and people. Add `q` for events that hold every word, newest first: [Calendar](../../app/calendar/).
- `GET /v1/chats?q=…` and `GET /v1/chats/{id}`: saved AI chats from Claude Code and Codex, each with its app.
- `GET /v1/notes?tag=…`: the notes on a topic and its parts.
- `GET /v1/memory?q=…`, `?tag=…`, `?source=…` or `?<column>=…`: facts in your memory, newest first. `GET /v1/memory/{id}` reads one fact, and `GET /v1/memory/columns` the memory's columns. [Memory and knowledge web](../knowledge-web/)

Times are a day, such as `2026-11-04`, or an ISO time. Add `timezone`, such as `Europe/London`, to read days and times in your zone. A long answer gives `nextCursor`: send it as `cursor` to read the next page.

## Add a note

```sh
curl https://<your-relay-server>/v1/notes \
  -H "Authorization: Bearer rek_…" \
  -H "Content-Type: application/json" \
  -d '{"clientId": "backup-2026-11-04-0001", "text": "Order the second PCB batch."}'
```

`clientId` is your own id for the note: 8 to 64 letters, digits or dashes. When you lose an answer, send the note again with the same `clientId`. The server keeps it once: the first call answers `201`, and a resend answers `200` with `"added": false`. The note shows with your key's or app's name as its device, and goes to your [webhooks](../../connections/your-database/) that take notes.

## Errors

A refused call answers with a status and an error:

```json
{ "error": "forbidden", "error_description": "This device key is turned off." }
```

| Status | `error` | When |
|---|---|---|
| `400` | `invalid_request` | A field is missing or wrong. `error_description` names it. |
| `401` | `invalid_token` | No token, an expired token, or a disconnected app. |
| `403` | `forbidden` | An unknown key, a phone's key, an older chat key, a turned-off key, an app that must connect again to add, or a key that is not a computer's on a route that only a computer's key can use. |
| `404` | `not_found` | No such note, chat or route in your own space. |
| `405` | `method_not_allowed` | The route doesn't take this method: the API never deletes. |
| `501` | `not_set_up` | The server has no knowledge web, as its Cloudflare account has no Artifacts. |
| `503` | `try_again` | Your knowledge web is still being made. Try again in a minute. |

[Web API reference](../v1-reference/) lists each route's fields.
