---
title: Set up the Pebble webhook
description: Send each note from your Pebble Index ring to your Relay server, with its words and recording.
---

Send each note from your Pebble Index ring to your Relay server, with its words and recording.

:::note
You need a Relay server and a key for the Pebble app first. [Connect a phone](../connect-a-phone/#make-the-key) shows how to make a key.
:::

## Steps

1. Make the Pebble app's key on the server's computer:
   ```sh
   node scripts/relay-device-key.mjs create --name "Pebble app"
   ```
2. In the Pebble app, open **Index 01 Settings**, then **Webhook**, then **Hold & talk**.
3. Enter your server's Pebble address:
   ```text
   https://<your-relay-server>/apps/relay/api/pebble
   ```
   The key's private page shows this address in full.
4. Add two custom headers with the values from the key's private page: `CF-Access-Client-Id` and `CF-Access-Client-Secret`.
5. Turn on **Sign requests**, and enter the signing secret. The owner of the Relay server gives you the secret on a private page.
6. Choose **Both**, so each note sends its words and its recording.
7. Tap **Send test event**. Relay answers `200` with `{ "ok": true, "test": true }` and keeps nothing from a test.
8. When the test shows success, tap **Save**.

## What is sent

| Field | What it holds |
|---|---|
| `audio` | The recording, m4a, 16 kHz |
| `transcription` | The words |
| `recordedAt` | When you spoke, in milliseconds |
| `X-Index-Delivery` | One id for each note. A note sent two times is kept once. |

## If a note doesn't arrive

- `401` means the signature or the time is wrong: check the signing secret, and the phone's clock.
- `403` means the key is wrong or turned off: check the two headers, or make a new key.
- After a `408`, `429` or `5xx`, the Pebble app tries again for 10 minutes.

[The Pebble webhook](../../api/pebble-webhook/) in the server API gives every field, header and answer.

## Next

[Notes](../../app/your-notes/) shows how ring notes appear in the app.
