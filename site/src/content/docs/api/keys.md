---
title: Keys
description: How a device proves who it is to the Relay Everything server, which routes its key reaches, and how to make and turn off a key on the page.
---

Each call to the Relay Everything server needs a key or a sign-in. A phone, the Pebble app and each Claude Code computer have their own device key, and a script has its own API key; a person in a browser signs in instead: [Sign up](../../start/sign-up/).

## Send a key

A device key starts with `rek_`. Send it in the `Authorization` header on each call:

```sh
curl https://<your-relay-server>/apps/relay/api/key \
  -H "Authorization: Bearer rek_…"
```

A call with a wrong key, or a key that is off, answers `403`.

## What a device key reaches

A device key only adds data, and only to the space of the person who made it. It reaches only these routes:

- `POST pebble`, `POST notes`, `POST health`, `POST locations`
- `GET key`, which answers the key's own device name and no data, so a device can check its key

Any other address or method answers `403` to a device key. To read, a person signs in on the Relay Everything page: `GET timeline`, `GET audio` and `GET summary` need a signed-in person, and each answers only from that person's own space. [Routes](../reference/) shows who can call each route.

## A chat key

A chat key is for the [Relay Everything plugin for Claude Code](../../connections/claude-code/). It reaches only `POST chats`, `POST chat-saves` and `GET key`: it can add chats, but it can't list, read, change or delete them, or reach a phone's routes. A phone's key can't reach the chat routes.

## An API key

An API key is for your own script or service. It reads your notes, health, places and chats, and adds notes, through the web API on your AI connector's address: [Connect a service](../connect-a-service/). On the Relay Everything server it reaches only `GET key`. A phone's key or a chat key can't open the web API.

## Make, list and turn off keys

You make and turn off your keys on your Relay Everything page, signed in:

| On the page | What it does |
|---|---|
| **Add a device** | Makes a key for a phone, the Pebble app, a Claude Code computer or a script. It shows once: as a QR code for a phone, or with a `curl` example for an API key. A Pebble device also gets its own signing secret, shown once with the key. |
| The list of devices | Shows each key: its name, its kind, when it was made, and whether it is off. |
| **Turn off** | Turns the key off at once. The other keys go on. |

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
| `401` | `authentication_required` | No one is signed in, or a Pebble webhook's signature or time is wrong. |
| `403` | `forbidden` | The key is off, on no list of devices, or calls a route it doesn't reach. |
| `413` | `invalid_input` | The body is too large. |
| `503` | `unavailable` | The server could not save or read. Send it again. |
| `500`, `504` | `internal_error`, `timeout` | Something failed on the server. Send it again later. |

The web API answers its errors in its own shape: [Connect a service](../connect-a-service/#errors).
