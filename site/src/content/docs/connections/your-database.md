---
title: Your own database
description: Add a webhook, and your Relay Everything server sends each new note, and the health and location you tick, to an address you own, in one signed format.
---

A webhook copies what your Relay Everything server stores in your space to an address you own, such as a small receiver beside your database. Your server sends each new note there a few seconds after it gets it. Health and location go only if you tick them.

Your data lives in your own space: one Durable Object with its own SQLite database, in the spaces Worker (`relay-everything-spaces`, or `<name>-spaces` on [your own server](../../start/run-your-own/)). The server's D1 database holds only the list of accounts: each person, their sign-ins and sessions, and a fingerprint of each key. Each webhook belongs to one person's space, and it sends only that person's data.

Only data that reached your server goes out. The app keeps notes on the phone until you turn on sending, so a note that stays on the phone never reaches a webhook.

## Add a webhook

1. Open your Relay Everything page, `https://<your-relay-server>/apps/relay/`, and sign in.
2. Under **Send to your database**, click **Add a webhook**.
3. Give it a name and its address. The address must start with `https://`. It can't be this computer, a private network, or your Relay Everything server itself.
4. Tick **Health** or **Location history** only for a database you control: they are sensitive. Notes always go.
5. Click **Add**, then copy the secret. Relay Everything shows it once. Your receiver uses it to check each message.
6. Click **Send a test**. The card shows the answer, such as *Answered 200 in 180 ms*.

A new webhook gets only data stored after you add it. To send earlier data too, click **Send past data** and pick a day.

Each card shows the webhook's state: **Working**, **Paused**, **Failing** or **Sending past data**, with what waits and the last answer. **New secret** replaces the secret, and the old one stops working at once. **Remove** deletes the webhook, its secret and its send history. Your notes stay in Relay Everything.

## The message

Every message is a `POST` with a JSON body in one envelope:

```json
{
  "version": 1,
  "type": "note.created",
  "timestamp": "2026-11-04T14:00:05.000Z",
  "data": { "note": { "...": "..." } }
}
```

`timestamp` is when Relay Everything stored what the message holds. Times are ISO 8601, in UTC. [`v1.schema.json`](../../webhooks/v1.schema.json) is the JSON Schema of every message. A change that breaks a receiver gets a new `version`.

| `type` | When | `data` holds |
|---|---|---|
| `note.created` | A note reaches your server. | `note`, with its words, time, place, device and recording |
| `note.updated` | A ring note gets its place from a later location batch. | `note`, without `audio` |
| `health.samples` | A phone sends health samples. | `samples`: up to 500 |
| `location.points` | A phone sends location points. | `points`: up to 500 |
| `webhook.test` | You click **Send a test**. | `webhook`: its `id` and `name` |

### `note.created`

```json
{
  "version": 1,
  "type": "note.created",
  "timestamp": "2026-11-04T14:01:02.000Z",
  "data": {
    "note": {
      "id": "a0000000-0000-4000-8000-000000000001",
      "source": "ring",
      "text": "Call the PCB fab about the second batch.",
      "recorded_at": "2026-11-04T14:01:00.000Z",
      "created_at": "2026-11-04T14:01:02.000Z",
      "device": { "id": "d0000000-0000-4000-8000-000000000002", "name": "Pebble app" },
      "place": { "lat": 43.6629, "lon": -79.3957, "accuracy": 15, "name": "Harbord St", "from": "history" },
      "audio": { "content_type": "audio/mp4", "base64": "AAAAGGZ0eXA..." }
    }
  }
}
```

`source` is `ring` or `typed`. `place` is null when the note has none. `from` says where the place came from: `phone` for a typed note's own place, `history` for the location point nearest a ring note. `audio` is a ring note's recording in base64, or null.

### `note.updated`

The same `note` as `note.created`, without `audio`. Relay Everything sends it when a ring note gets its place after it arrived. Update the note's row by its `id`.

### `health.samples`

```json
{
  "version": 1,
  "type": "health.samples",
  "timestamp": "2026-11-04T19:00:00.000Z",
  "data": {
    "samples": [
      { "id": 2, "device": { "id": "d0000000-0000-4000-8000-000000000001", "name": "Android phone" }, "type": "steps",
        "start": "2026-11-04T14:00:00.000Z", "end": "2026-11-04T18:00:00.000Z", "value": 5210, "unit": "count",
        "source": "com.google.android.apps.fitness" }
    ]
  }
}
```

`type` is `steps`, `heart_rate`, `sleep` or `workout`.

### `location.points`

```json
{
  "version": 1,
  "type": "location.points",
  "timestamp": "2026-11-04T19:00:00.000Z",
  "data": {
    "points": [
      { "id": 1, "device": { "id": "d0000000-0000-4000-8000-000000000001", "name": "Android phone" },
        "at": "2026-11-04T14:00:00.000Z", "lat": 43.6629, "lon": -79.3957, "accuracy": 15, "place": "Harbord St" }
    ]
  }
}
```

## Check the signature

Relay Everything signs each message by [Standard Webhooks](https://www.standardwebhooks.com/), which has ready libraries for most languages. Each message has three headers:

| Header | Holds |
|---|---|
| `webhook-id` | The message's id. A retry sends the same id. |
| `webhook-timestamp` | When this try was sent, in Unix seconds. |
| `webhook-signature` | `v1,` and the base64 HMAC-SHA256 of `{webhook-id}.{webhook-timestamp}.{body}` |

The HMAC key is the secret without its `whsec_` start, decoded from base64. Refuse a message with a wrong signature, or a timestamp more than 5 minutes old. With a library, in Node:

```js
import { Webhook } from 'standardwebhooks';

const payload = new Webhook(process.env.RELAY_WEBHOOK_SECRET).verify(body, headers);
```

## Order, retries and repeats

- Each webhook gets every item it takes, in the order Relay Everything stored them, with none skipped.
- Answer with a `2xx` status within 15 seconds. Relay Everything does not follow a redirect.
- After any other answer, Relay Everything tries the same message again after 30 s, 2 min, 10 min, 30 min, 1 h, 2 h, 4 h, 6 h and 8 h: about a day. Then the card shows **Failing**, with the last answer and how many items wait. If a send is lost, your space wakes itself every 15 minutes while it has a webhook, and sends what waits. **Try again now** sends them all, in order, from where it stopped.
- A retry can send a message you already saved, when your answer was lost. Its id and body are the same. So save each note, sample and point by its `id`, as an upsert.
- Accept bodies up to 16 MB. A ring note's recording is about 100 KB a minute, and base64 makes it a third larger.

## Tables in Postgres

```sql
CREATE TABLE relay_notes (
  id uuid PRIMARY KEY,
  source text NOT NULL,
  text text NOT NULL,
  recorded_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL,
  device_id text NOT NULL,
  device_name text NOT NULL,
  lat double precision,
  lon double precision,
  place text,
  audio bytea
);
CREATE TABLE relay_health_samples (
  id bigint PRIMARY KEY,
  device_id text NOT NULL,
  type text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  value double precision NOT NULL,
  unit text NOT NULL,
  source text NOT NULL
);
CREATE TABLE relay_location_points (
  id bigint PRIMARY KEY,
  device_id text NOT NULL,
  at timestamptz NOT NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision NOT NULL,
  place text
);
```

Save a note with `INSERT ... ON CONFLICT (id) DO UPDATE`, and keep the stored `audio` when a `note.updated` has none.

## An example receiver

[`receiver.mjs`](../../webhooks/receiver.mjs) is about 60 lines of Node with no packages. It checks each signature and saves notes, samples and points in a SQLite file, so it needs no database server. It needs Node 22.13 or later.

```bash
curl -O https://relayeverything.com/webhooks/receiver.mjs
RELAY_WEBHOOK_SECRET=whsec_... PORT=8787 DATABASE=relay.sqlite node receiver.mjs
```

Your Relay Everything server must reach it at an `https` address. To try it from your own computer, put it behind a tunnel, such as `cloudflared tunnel --url http://localhost:8787`, and add the tunnel's address as the webhook.
