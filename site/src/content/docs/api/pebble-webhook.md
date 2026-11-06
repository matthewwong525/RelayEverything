---
title: Pebble webhook
description: The route that takes a ring note from the Pebble app's Index webhook, its fields, signature and answers.
---

`POST /apps/relay/api/pebble` takes a ring note from the Pebble app's Index webhook, version 1. [Set up the Pebble webhook](../../start/pebble-webhook/) gives the steps in the Pebble app; this page gives the details.

## Headers

| Header | What it holds |
|---|---|
| `Authorization` | `Bearer` and the Pebble device's [key](../keys/), as a custom header |
| `X-Index-Webhook-Version` | `1` |
| `X-Index-Timestamp` | When the Pebble app sent it, in Unix seconds. It must be within 300 s of the server's time. |
| `X-Index-Delivery` | One id for each note: 1 to 200 letters, digits and `. _ : -` |
| `X-Index-Trigger` | What started the note |
| `X-Index-Test` | `true` on a test event |
| `X-Index-Signature` | The signature, as 64 lowercase hex characters |

## Body

A `multipart/form-data` body, up to 10 MB:

| Field | What it holds |
|---|---|
| `audio` | The recording, m4a, 16 kHz (optional) |
| `transcription` | The words (optional) |
| `recordedAt` | When you spoke, in Unix milliseconds |

## Signature

The signature is HMAC-SHA256, keyed with the UTF-8 bytes of the device's own signing secret, which the page shows once with its key, over this text followed by the raw body:

```text
v1\n{X-Index-Timestamp}\n{X-Index-Delivery}\n{X-Index-Trigger}\n{1 for a test, else 0}\n
```

## Answers

The server checks the key first, as it needs the device's own signing secret. Then it checks in this order: version, time, delivery id, size and signature.

| Status | Body | When |
|---|---|---|
| `200` | `{ "ok": true, "id": "..." }` | The note is kept. |
| `200` | `{ "ok": true, "duplicate": true }` | This delivery id was kept before. Nothing is kept two times. |
| `200` | `{ "ok": true, "test": true }` | A test event: checked, then dropped. |
| `400` | an error | Wrong version, time or delivery id, or no readable `recordedAt` |
| `401` | an error | The time is more than 300 s off, or the signature is wrong. |
| `403` | an error | The key is not a device key, it is off, or it is a chat key. |
| `413` | an error | The body is larger than 10 MB. |
| `503` | an error | The recording could not be saved. The Pebble app sends it again. |

The Pebble app tries again after a `408`, `429` or `5xx`, for up to 10 minutes. The delivery id makes a retry safe.

## A note's place

The webhook carries no place. The server gives a ring note the phone's location history point nearest in time, up to 10 minutes before or after `recordedAt`. A point that arrives later fills it in then.
