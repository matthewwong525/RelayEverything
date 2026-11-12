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

A device key reaches only the space of the person who made it. It adds data there, and a phone's key also syncs your notes. It reaches only these routes:

- `POST notes`, `POST attachments`, `POST health`, `POST locations`, `POST calendar`, `POST photos`
- `PATCH notes`, which changes the words of a note that the same phone key sent, and adds its new files. A phone key can not change another device's note: the server answers `404`.
- `GET key`, which answers the key's own device name and no data, so a device can check its key
- For a phone's key only:
  - `GET notes`, which answers the notes added or changed since the phone's last sync, from every device and way in, so each signed-in phone shows all your notes
  - `GET attachment` and `GET audio`, which open a note's file and an older recorded note's recording, when you tap one in the app
  - `PATCH notes`, which changes the words of any note in your space, by its `id`, or of the phone's own note, by its `clientId`. It adds new files only to a note the same phone sent. When the note changed later on another phone, the server keeps the newer words and answers `409`.
  - `PUT notes/pin`, which pins or unpins any note in your space, by its `id`, or the phone's own note, by its `clientId`. When the note's pin changed later on another phone, the server keeps the newer pin and answers `409`.
  - `GET connections`, which answers your account's email, the names of your phones and computers, the names of your AI apps with the day each connected, the names of your webhooks, and your two notes addresses, for the account card, the **Account** page, **Connect your AI** and **Email notes** in the app. It answers no key and no webhook address, secret or send state.
  - `POST devices/off`, which signs out one of your phones, for **Phones** on the app's **Account** page. It can't sign out a computer or an API key, or add a key, an AI app or a webhook.

Any other address or method answers `403` to a device key. A phone's key can't read your health, calendar, places, chats or photos, or delete anything: `GET timeline`, `GET summary`, `GET photos` and `POST photos/delete` need a signed-in person, and each answers only from that person's own space. A phone's key reads your notes until you sign the phone out, so sign out a lost phone at once: [Sign out a lost phone](../../start/connect-a-phone/#sign-out-a-lost-phone). [Routes](../reference/) shows who can call each route.

## A computer's key

A computer's key is for the [Relay Everything plugin for Claude Code and Codex](../../connections/claude-code/). You don't make it on the page: type `/relay:connect` on the computer, then click **Connect** on the page it opens. On the Relay Everything server it reaches only `POST chats`, `POST chat-saves` and `GET key`: it adds chats, but it can't list, read, change or delete them here, or reach a phone's routes. It reads your data and adds notes through the [web API](../connect-a-service/), as an API key does. **Connect your AI** lists it under **Claude Code and Codex**, with **Disconnect** on the web.

## A chat key

A chat key is the older key of the plugin for Claude Code, made before the computer's key. It reaches only `POST chats`, `POST chat-saves` and `GET key`, and it can't open the web API. To read your data from the chat too, type `/relay:connect` on that computer, then disconnect the old key in **Connect your AI**. A phone's key can't reach the chat routes.

## An API key

An API key is for your own script or service. It reads your notes, health, places and chats, and adds notes, through the web API on your AI connector's address: [Connect a service](../connect-a-service/). On the Relay Everything server it reaches only `GET key`. A phone's key or a chat key can't open the web API.

## Make, list and turn off keys

A phone or a computer gets its key only by signing in. Your Relay Everything page makes only API keys, with no phone key and no QR code. Signed in on the page, open **Settings**, then **Account**. Under **Advanced**, click **API keys**: *For your own scripts*.

| On the API keys page | What it does |
|---|---|
| **Add an API key** | Makes an API key for your own script. Give it a name, then click **Make the key**. It shows once, with a `curl` example. |
| The list of API keys | Shows each API key: its name, when it was made, and whether it is off. |
| **Turn off** | Turns the key off at once. The other keys go on. |

The other keys are on other pages:

| Key | Where it shows | To stop it |
|---|---|---|
| A phone's key | **Phones**, on the **Account** page in the app and on the web | **Sign out** beside the phone |
| A computer's key, or an older chat key | **Claude Code and Codex**, in **Connect your AI** | **Disconnect** beside the computer, on the web |

A phone gets its key when you sign in: in the Relay Everything app, open Settings, tap **Sign in to Relay Everything**, then **Sign in**. The app opens your sign-in, the page asks **Connect this phone?**, and **Connect** makes the phone's key. The key goes straight to the phone and never shows, and the phone shows under **Phones**.

The app and the server use these addresses for it. You don't call them yourself:

| Address | What it does |
|---|---|
| `GET /apps/relay/sign-in/phone?challenge=…&name=…` | Signs you in if you aren't, then asks **Connect this phone?** |
| `POST /apps/relay/sign-in/phone` | **Connect** sends the app a code that works once, for 5 minutes. **Cancel** tells the app. |
| `POST /apps/relay/sign-in/phone/key` | The app trades the code, with a secret only it holds, for its key: `{ "server": "…", "key": "rek_…" }`. A code used twice, too old, or with the wrong secret answers `400`. |

Relay Everything keeps only a fingerprint of each key, never the key itself, so a lost key can't be shown again: sign in again on the device, or add a new API key. A preview of Relay Everything's own server has its own accounts and keys. A preview's key doesn't open the live server, and a live key doesn't open a preview.

A server you run yourself makes its API keys on the page too. An older server gets this with its next update: [Run your own server](../../start/run-your-own/#update-it).

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
