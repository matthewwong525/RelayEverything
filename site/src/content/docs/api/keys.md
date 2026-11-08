---
title: Keys
description: How a device proves who it is to the Relay Everything server, which routes its key reaches, and how to make and turn off a key on the page.
---

Each call to the Relay Everything server needs a key or a sign-in. Each phone and each Claude Code computer has its own device key, and a script has its own API key; a person in a browser signs in instead: [Sign up](../../start/sign-up/).

## Send a key

A device key starts with `rek_`. Send it in the `Authorization` header on each call:

```sh
curl https://<your-relay-server>/apps/relay/api/key \
  -H "Authorization: Bearer rek_…"
```

A call with a wrong key, or a key that is off, answers `403`.

## What a device key reaches

A device key only adds data, and only to the space of the person who made it. It reaches only these routes:

- `POST notes`, `POST attachments`, `POST health`, `POST locations`
- `PATCH notes`, which changes the words of a note that the same phone key sent, and adds its new files. A phone key can not change another device's note: the server answers `404`.
- `GET key`, which answers the key's own device name and no data, so a device can check its key

Any other address or method answers `403` to a device key. To read, a person signs in on the Relay Everything page: `GET timeline`, `GET audio`, `GET attachment` and `GET summary` need a signed-in person, and each answers only from that person's own space. [Routes](../reference/) shows who can call each route.

## A chat key

A chat key is for the [Relay Everything plugin for Claude Code](../../connections/claude-code/). It reaches only `POST chats`, `POST chat-saves` and `GET key`: it can add chats, but it can't list, read, change or delete them, or reach a phone's routes. A phone's key can't reach the chat routes.

## An API key

An API key is for your own script or service. It reads your notes, health, places and chats, and adds notes, through the web API on your AI connector's address: [Connect a service](../connect-a-service/). On the Relay Everything server it reaches only `GET key`. A phone's key or a chat key can't open the web API.

## Make, list and turn off keys

You make and turn off your keys on your Relay Everything page, signed in:

| On the page | What it does |
|---|---|
| **Add a device** | Makes a key for a phone, a Claude Code computer or a script. It shows once: as a QR code for a phone, or with a `curl` example for an API key. |
| The list of devices | Shows each key: its name, its kind, when it was made, and whether it is off. |
| **Turn off** | Turns the key off at once. The other keys go on. |

A phone can also get its key with no QR code: in the Relay Everything app, tap **Sign in to connect**. The app opens your sign-in, the page asks **Connect this phone?**, and **Connect** makes the phone's key. The key goes straight to the phone and never shows. It works like a key from **Add a device**, and the phone shows in your list of devices.

The app and the server use these addresses for it. You don't call them yourself:

| Address | What it does |
|---|---|
| `GET /apps/relay/sign-in/phone?challenge=…&name=…` | Signs you in if you aren't, then asks **Connect this phone?** |
| `POST /apps/relay/sign-in/phone` | **Connect** sends the app a code that works once, for 5 minutes. **Cancel** tells the app. |
| `POST /apps/relay/sign-in/phone/key` | The app trades the code, with a secret only it holds, for its key: `{ "server": "…", "key": "rek_…" }`. A code used twice, too old, or with the wrong secret answers `400`. |

Relay Everything keeps only a fingerprint of each key, never the key itself, so a lost key can't be shown again: add the device again for a new key. A preview of Relay Everything's own server has its own accounts and keys. A preview's key doesn't open the live server, and a live key doesn't open a preview.

A server you run yourself makes its keys on the page too. An older server gets this with its next update: [Run your own server](../../start/run-your-own/#update-it).

## Errors

A refused call answers with a status and an error:

```json
{ "error": { "code": "forbidden", "message": "This device key is turned off." } }
```

| Status | Code | When |
|---|---|---|
| `400` | `invalid_input` | A field is missing or wrong. The answer's `issues` names each field. |
| `401` | `authentication_required` | No one is signed in. |
| `403` | `forbidden` | The key is off, on no list of devices, or calls a route it doesn't reach. |
| `413` | `invalid_input` | The body is too large. |
| `503` | `unavailable` | The server could not save or read. Send it again. |
| `500`, `504` | `internal_error`, `timeout` | Something failed on the server. Send it again later. |

The web API answers its errors in its own shape: [Connect a service](../connect-a-service/#errors).
