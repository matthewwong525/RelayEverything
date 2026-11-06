---
title: Keys
description: How a device proves who it is to the Relay Everything server, which routes its key reaches, and how to turn a key off.
---

Each call to the Relay Everything server needs a key. A phone and the Pebble app each have their own device key; a person in a browser signs in instead.

## Send a key

A device key is a pair of values. Send both as headers on each call:

```sh
curl https://<your-relay-server>/apps/relay/api/key \
  -H "CF-Access-Client-Id: <client id>" \
  -H "CF-Access-Client-Secret: <client secret>"
```

A call with no key, or a wrong one, stops at the server's login and never reaches Relay Everything.

## What a device key reaches

A device key only adds data. It reaches only these routes:

- `POST pebble`, `POST notes`, `POST health`, `POST locations`
- `GET key`, which answers the key's own device name and no data, so a device can check its key

Any other address or method answers `403` to a device key. To read, a person signs in on the Relay Everything page: `GET timeline`, `GET audio` and `GET summary` need a signed-in person. [Routes](../reference/) shows who can call each route.

## A chat key

A chat key, made with `--for claude-code`, is for the [Relay Everything plugin for Claude Code](../../connections/claude-code/). It reaches only `POST chats`, `POST chat-saves` and `GET key`: it can add chats, but it can't list, read, change or delete them, or reach a phone's routes. A phone's key can't reach the chat routes.

## Make, list and turn off keys

The owner of the Relay Everything server runs these on the computer that holds the server's project. On [your own server](../../start/run-your-own/), that is the computer where you made it:

| Command | What it does |
|---|---|
| `node scripts/relay-device-key.mjs create --name "Android phone"` | Makes a key. It shows once, as a QR code and on a private page. It lasts one year. |
| `node scripts/relay-device-key.mjs create --name "Laptop" --for claude-code` | Makes a chat key. Its connect code shows once, in the terminal and on a private page. |
| `node scripts/relay-device-key.mjs list` | Lists each key: its name, its kind (`phone` or `claude-code`), when it was made, and whether it is off. |
| `node scripts/relay-device-key.mjs revoke --name "Android phone"` | Turns the key off at once. The other keys go on. |

Add `--staging` to make a key for a preview of Relay Everything's own server; your own server has no previews. A preview's key doesn't open the live server, and a live key doesn't open a preview.

## Errors

A refused call answers with a status and an error:

```json
{ "error": { "code": "forbidden", "message": "This device key is turned off." } }
```

| Status | Code | When |
|---|---|---|
| `400` | `invalid_input` | A field is missing or wrong. The answer's `issues` names each field. |
| `401` | `authentication_required` | A Pebble webhook's signature or time is wrong. |
| `403` | `forbidden` | The key is off, on no list of devices, or calls a route it doesn't reach. |
| `413` | `invalid_input` | The body is too large. |
| `503` | `unavailable` | The server could not save or read. Send it again. |
| `500`, `504` | `internal_error`, `timeout` | Something failed on the server. Send it again later. |
