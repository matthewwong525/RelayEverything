---
title: Connect a service
description: Let your own script or service read your Relay Everything notes, health, places and chats, and add notes, through the web API with an API key or your own sign-in.
---

The web API lets your own script or service read your Relay Everything data and add notes. It answers the same questions as the [AI connector](../../connections/connect-your-ai/), as plain HTTP with JSON. It reads, and it adds notes. It can't change or delete your notes. With Google connected, it also passes your requests to your own Google: [Google](#google).

The web API is on your AI connector's address, under `/v1/`. When the connector is at `https://<your-relay-server>/mcp`, the API is at `https://<your-relay-server>/v1/`. The **AI apps** card on your Relay Everything page shows the connector's address.

Each caller reaches only the space of the person who made its key or connected it. There are two ways in.

## With an API key

An API key is for a script or a service that runs on its own, such as a backup job.

1. On your Relay Everything page, click **Add a device** and pick **API key**.
2. Give it a name you know it by, then click **Make the key**. The page shows the key once, with a `curl` example.
3. Keep the key in your script's secret store. Never put it in a file you share.

Send the key in the `Authorization` header on each call:

```sh
curl https://<your-relay-server>/v1/me \
  -H "Authorization: Bearer rek_…"
```

`GET /v1/me` answers the key's name and whether it may add notes. It reads no data, so it is a safe first call.

An API key works only on the web API. On the Relay Everything server it reaches only `GET key`. A phone's key or a chat key can't open the web API: make an API key for it. To stop a key, click **Turn off** beside it in your list of devices. [Keys](../keys/) tells more.

## With your own sign-in

An app that has its own users signs each person in with OAuth, as the Claude app does.

1. Register the app at `https://<your-relay-server>/register` (OAuth dynamic client registration).
2. Send the person to `/authorize` with PKCE (S256). They click **Connect**, then sign in to Relay Everything.
3. Trade the code at `/token` for an access token and a refresh token.

Leave out `resource`, or send `https://<your-relay-server>/mcp` as it. The same token then works on `/mcp` and on `/v1/`. An access token lasts one hour; refresh it at `/token`. The app shows on the person's **AI apps** card, and **Disconnect** stops it at once. An app connected before the API could add notes only reads: connect it again to add.

The [OpenAPI file](/api/v1.openapi.json) names each step's address. Load it into Swagger, Postman or a code generator to make a client.

## Read

```sh
curl "https://<your-relay-server>/v1/notes?q=milk&limit=5" \
  -H "Authorization: Bearer rek_…"
```

- `GET /v1/notes?q=…`: notes that hold every word, newest first. Without `q`, give `from` and `to` for every note in that time.
- `GET /v1/notes/{id}`: one note, the places near it in time, and its day's health totals.
- `GET /v1/days/{day}`: one day's notes count, steps, sleep, heart rate, workouts and places.
- `GET /v1/health?type=steps&from=…&to=…`: health values, one per hour or per day.
- `GET /v1/places?from=…&to=…`: each stay at a place.
- `GET /v1/chats?q=…` and `GET /v1/chats/{id}`: saved Claude Code chats.

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
| `403` | `forbidden` | An unknown key, a phone or chat key, a turned-off key, an app that must connect again to add or to reach Google, no Google connected, or a delete for ever. |
| `404` | `not_found` | No such note, chat or route in your own space. |
| `405` | `method_not_allowed` | The route doesn't take this method: the API never changes or deletes your notes. Google takes no HEAD, and Contacts take only GET. |
| `503` | `temporarily_unavailable` | A Google request on a server that does not connect Google, or when Google's sign-in can't be renewed: try again. |

[Web API reference](../v1-reference/) lists each route's fields.

## Google

After you [connect Google](../../connections/google/), an API key, or an app connected after that, reaches your Gmail, Calendar, Drive and Contacts under `/v1/google/<service>/`. Send Google's own path after it as is, with its slashes not encoded, and Google's query as the request's own query. Any method Google takes but HEAD works:

```sh
curl "https://<your-relay-server>/v1/google/gmail/messages?q=from%3Asam&maxResults=5" \
  -H "Authorization: Bearer rek_…"
```

The answer is Google's own status, type and body, as it comes. A Drive upload goes to `/v1/google/drive/upload/…`; a resumable upload's `Location` points back to your server. Relay Everything refuses these before Google sees them:

- a delete for ever of an email, a thread, a draft or a Drive file: put it in the bin;
- a Gmail path that names another mailbox than `users/me/`;
- a change to Contacts, which only read;
- no Google connected (`403`), or an app connected before Google (`403`: connect it again).

[Connect Google](../../connections/google/#from-a-script) lists the four services' paths.
