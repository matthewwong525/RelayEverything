---
title: Keys
description: How a device proves who it is to the Relay server, which routes its key reaches, and how to turn a key off.
---

Each call to the Relay server needs a key. A phone and the Pebble app each have their own device key; a person in a browser signs in instead.

## Send a key

A device key is a pair of values. Send both as headers on each call:

```sh
curl https://<your-relay-server>/apps/relay/api/timeline?limit=5 \
  -H "CF-Access-Client-Id: <client id>" \
  -H "CF-Access-Client-Secret: <client secret>"
```

A call with no key, or a wrong one, stops at the server's login and never reaches Relay.

## What a device key reaches

A device key reaches only these routes:

- `POST pebble`, `POST notes`, `POST health`, `POST locations`
- `GET timeline`, `GET audio`

Any other address answers `403` to a device key. `GET summary` needs a signed-in person. [Routes](../reference/) shows who can call each route.

## Make, list and turn off keys

The owner of the Relay server runs these on the computer that holds the server's project:

| Command | What it does |
|---|---|
| `node scripts/relay-device-key.mjs create --name "Android phone"` | Makes a key. It shows once, as a QR code and on a private page. It lasts one year. |
| `node scripts/relay-device-key.mjs list` | Lists each key: its name, when it was made, and whether it is off. |
| `node scripts/relay-device-key.mjs revoke --name "Android phone"` | Turns the key off at once. The other keys go on. |

Add `--staging` to make a key for a preview. A preview's key doesn't open the live server, and a live key doesn't open a preview.

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
