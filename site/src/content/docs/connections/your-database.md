---
title: Your own database
description: Add a webhook, and your Relay Everything server or your phone sends each new note, and the health, calendar and location you pick, to an address you own, in one signed format.
---

A webhook copies what your Relay Everything server stores in your space to an address you own, such as a small receiver beside your database. Your server sends each new note there a few seconds after it gets it, then each of its files in a [`note.file`](#notefile) message. When the phone changes a note, the note goes again as [`note.updated`](#noteupdated). Health, calendar and location go only if you tick them.

Your data lives in your own space: one Durable Object with its own SQLite database, in the spaces Worker (`relay-everything-spaces`, or `<name>-spaces` on [your own server](../../start/run-your-own/)). The server's D1 database holds only the list of accounts: each person, their sign-ins and sessions, and a fingerprint of each key. Each webhook belongs to one person's space, and it sends only that person's data.

Only data that reached your server goes out. The app keeps notes on the phone until you turn on sending, so a note that stays on the phone never reaches a webhook.

To keep your data off Relay Everything completely, [send from the phone](#send-from-the-phone) straight to your webhook instead.

## Add a webhook

1. Open your Relay Everything page, `https://<your-relay-server>/apps/relay/`, and sign in.
2. Under **Send to your database**, click **Add a webhook**.
3. Give it a name and its address. The address must start with `https://`. It can't be this computer, a private network, or your Relay Everything server itself.
4. Tick **Health**, **Calendar** or **Location history** only for a database you control: they are sensitive. Notes always go.
5. Click **Add**, then copy the secret. Relay Everything shows it once. Your receiver uses it to check each message.
6. Click **Send a test**. The card shows the answer, such as *Answered 200 in 180 ms*.

A new webhook gets only data stored after you add it. To send earlier data too, click **Send past data** and pick a day.

Each card shows the webhook's state: **Working**, **Paused**, **Failing** or **Sending past data**, with what waits and the last answer. **New secret** replaces the secret, and the old one stops working at once. **Remove** deletes the webhook, its secret and its send history. Your notes stay in Relay Everything.

## Send from the phone

The phone app can send to your own webhook itself, with no Relay Everything account, sign-in or key. Your receiver gets the same messages, signed the same way, so one receiver works for both. The phone sends to your server or to your webhook, never both.

1. Start your receiver at an `https://` address. A home address, such as your own computer on your Wi-Fi, is allowed. The phone does not take a self-made certificate.
2. In the app, open **Settings** and turn on **Send my notes**.
3. Pick **My own webhook**, and type your receiver's address.
4. Click **Copy**, and give the secret to your receiver. You can also paste your receiver's own `whsec_` secret.
5. Click **Send a test**. The app shows your receiver's answer, such as *Your receiver answered 204. It works.*
6. Click **Save**. The app asks if your earlier notes go too.

Settings then says *To your webhook*, with your receiver's address. Turn on **Health**, **Calendar** or **Location history** to send them too. The phone sends each new note, then each of its files in a [`note.file`](#notefile) message.

What you give up:

- **Data comes in groups, not live.** The phone sends only while it is on and has signal, and the phone's own limits choose when the app runs in the background.
- **Your Relay Everything page and your AI can not read it**, because none of it is on the server.
- **A failing receiver holds back the rest.** The phone sends in order, so it keeps each item, and all after it, until your receiver answers `2xx`. Settings shows the last answer. It never drops an item for a `400`. Only a file your receiver refuses with `413` is dropped, and Settings names it.

From the phone, `device.id` is the phone's own id, a UUID the app makes once. A note's `created_at` is the same as its `recorded_at`: the note's own time, which for a voice note is when it was recorded. Its `note.updated` has the same one. The message's `timestamp` is when the phone queued the message. Health samples and points are numbered on the phone, so save them by `device.id` and `id` together. A calendar event's `id` is made from the phone's id and the event's `key`, so each change of one event has the same `id`. A removed event from the phone has only its `key`, `id` and `start`.

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

`timestamp` is when Relay Everything, or the phone that sends to your webhook, stored what the message holds. Times are ISO 8601, in UTC. [`v1.schema.json`](../../webhooks/v1.schema.json) is the JSON Schema of every message. It accepts a field it does not list, so a saved copy still passes a message with a new field. The format can still get new types, fields and values: see [when the format changes](#when-the-format-changes).

| `type` | When | `data` holds |
|---|---|---|
| `note.created` | A note reaches your server. | `note`, with its words, time, place, device, recording, and the names of its files |
| `note.updated` | The phone that sent a note changes it. Always after the note's `note.created`. | `note`, with its latest words, without `audio` |
| `health.samples` | A phone sends health samples. | `samples`: up to 500 |
| `location.points` | A phone sends location points. | `points`: up to 500 |
| `calendar.events` | A phone sends new, changed or removed calendar events. | `events`: up to 500, each with its `status` |
| `note.file` | A file of a note reaches your server, or the phone sends it: one message for each file, after the note. | `note_id`, and `file` with its bytes |
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
      "device": { "id": "d0000000-0000-4000-8000-000000000001", "name": "Android phone" },
      "place": { "lat": 43.6629, "lon": -79.3957, "accuracy": 15, "name": "Harbord St", "from": "history" },
      "audio": { "content_type": "audio/mp4", "base64": "AAAAGGZ0eXA..." }
    }
  }
}
```

`source` is `ring` or `typed`. `place` is null when the note has none. `from` says where the place came from: `phone` for a typed note's own place, `history` for an older ring note's place, taken from the location history. Relay Everything gives no note a place this way now. `audio` is a ring note's recording in base64, or null.

### A note's files

A note from the phone can hold up to 10 files, such as photos and PDFs. Only a note with files has an `attachments` list in its `note.created` message. A note without files gets the message above, with no `attachments` field.

```json
"attachments": [
  { "id": "3f9c2a7be1d04c58a6f0b2e4d7c91a05", "name": "warranty.pdf", "content_type": "application/pdf", "size": 245760 }
]
```

| Field | Holds |
|---|---|
| `id` | The file's id, from the phone. A resend has the same id. |
| `name` | The file's name, such as `warranty.pdf` |
| `content_type` | Its type, such as `application/pdf` or `image/jpeg` |
| `size` | Its size in bytes, up to 25 MB |

The message holds no file bytes, because a file can be too big for one message. Each file comes after it, in its own `note.file` message. From your server, that message goes when the file's bytes reach your space, which can be some time after the note.

### `note.file`

Your server sends it when it stores a file of a note, and the phone sends it when it sends to your own webhook. It holds one file, with its bytes in base64, and comes after the note's `note.created`. Save it by the file's `id`, beside its note.

```json
{
  "version": 1,
  "type": "note.file",
  "timestamp": "2026-11-04T14:01:02.000Z",
  "data": {
    "note_id": "3f9a0c1d2e4b5a6978c1d2e3f4a5b6c7",
    "file": { "id": "3f9c2a7be1d04c58a6f0b2e4d7c91a05", "name": "warranty.pdf", "content_type": "application/pdf",
      "size": 245760, "base64": "JVBERi0xLjcK..." }
  }
}
```

A 25 MB file makes a body of about 33 MB. Accept bodies that large, or answer `413`: Relay Everything, or the phone, then skips that file and sends the rest. The webhook's card, or the phone's Settings, names the skipped file. A file your receiver skips stays on your Relay Everything page. Every other failed answer is tried again, as for every message.

Files that your server stored before it sent `note.file` go once to each webhook, in the order of their notes.

### `note.updated`

Relay Everything sends `note.updated` when the phone that sent a note changes the note's words or adds a file to it. Your server sends it to every active webhook, and the phone sends it to your own webhook. It always comes after the note's `note.created`. Each new file then comes in its own [`note.file`](#notefile).

```json
{
  "version": 1,
  "type": "note.updated",
  "timestamp": "2026-11-04T15:20:00.000Z",
  "data": {
    "note": {
      "id": "a0000000-0000-4000-8000-000000000002",
      "source": "typed",
      "text": "# Small things to buy\n- [x] Lemons\n- [ ] Green tea",
      "recorded_at": "2026-11-04T14:01:00.000Z",
      "created_at": "2026-11-04T14:01:02.000Z",
      "device": { "id": "d0000000-0000-4000-8000-000000000001", "name": "Android phone" },
      "place": null,
      "edited_at": "2026-11-04T15:20:00.000Z"
    }
  }
}
```

It holds the same `note` as `note.created`, with its latest words and without `audio`. `edited_at` is when the phone changed the note; an older `note.updated` has none. `attachments` lists all the note's files, as in `note.created`, and only a note with files has it. Update the note's row by its `id`, and keep its stored `audio`. A changed note has the same `id`, `recorded_at` and `created_at`.

The words keep their styles as Markdown marks, such as `#` for a title, `- [ ]` and `- [x]` for a checklist, and `<u>…</u>` for underline. A receiver that ignores `note.updated` keeps working: it keeps the words from `note.created`.

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

`type` is one of these, each in one fixed `unit`:

| `type` | `unit` |
|---|---|
| `steps` | `count` |
| `heart_rate`, `resting_heart_rate` | `bpm` |
| `sleep`, `workout`, `mindful` | `min` |
| `weight` | `kg` |
| `hrv_sdnn` (iPhone), `hrv_rmssd` (Android) | `ms` |
| `blood_oxygen` | `%`, from 0 to 100 |
| `blood_pressure_systolic`, `blood_pressure_diastolic` | `mmHg` |
| `cycle_flow` | `0` none, `1` light, `2` medium, `3` heavy |
| `water` | `ml` |

A blood pressure reading is two samples with the same `start`: the upper and the lower number. A later version can add a type, so keep a sample whose `type` you do not know.

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

### `calendar.events`

```json
{
  "version": 1,
  "type": "calendar.events",
  "timestamp": "2026-11-04T19:00:00.000Z",
  "data": {
    "events": [
      { "id": 7, "status": "changed", "device": { "id": "d0000000-0000-4000-8000-000000000001", "name": "iPhone" },
        "key": "work:5F1C2B:1762264800000", "calendar": "Work", "title": "Board meeting",
        "start": "2026-11-04T14:00:00.000Z", "end": "2026-11-04T15:00:00.000Z", "all_day": false,
        "location": "Office, room 2", "notes": null, "url": null,
        "people": [{ "name": "Sam Lee", "email": "sam@…", "organizer": true }] }
    ]
  }
}
```

`status` is `changed` for a new or changed event, and `removed` for an event deleted on the phone or in a calendar turned off. Each time of a repeating event has its own `key`, and a resend of the same event has the same `key`. Save each event by its `id` as an upsert, and delete or mark the row when `status` is `removed`.

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

- Each webhook gets every item it takes, in the order Relay Everything stored them, with none skipped but a file your receiver refuses with `413`.
- Answer with a `2xx` status within 15 seconds. Relay Everything does not follow a redirect.
- After any other answer, Relay Everything tries the same message again after 30 s, 2 min, 10 min, 30 min, 1 h, 2 h, 4 h, 6 h and 8 h: about a day. Then the card shows **Failing**, with the last answer and how many items wait. If a send is lost, your space wakes itself every 15 minutes while it has a webhook, and sends what waits. **Try again now** sends them all, in order, from where it stopped.
- A retry can send a message you already saved, when your answer was lost. Its id and body are the same. So save each note, sample, point and event by its `id`, as an upsert.
- From your server, accept bodies up to 34 MB. A ring note's recording is about 100 KB a minute, a file is up to 25 MB, and base64 makes each a third larger. To accept less, answer `413` to a `note.file` that is too large.

## When the format changes

Relay Everything gets new kinds of data often. Each new kind comes with new messages, so build your receiver to accept what it does not know:

- **Answer `2xx` to a `type` you do not know.** Keep its body, or ignore it. A refusal makes Relay Everything try the same message again for about a day, and the webhook then shows as **Failing**.
- **Keep a field you do not know**, and do not refuse the message for it. A message can get a new field, such as a note's `attachments`.
- **Accept a new value in a list**, such as a new health `type` or a new calendar event `status`. The schema gives these as text, with the values known today as examples.

A new kind of data goes to a webhook only when you tick it. A webhook you added before gets nothing new by itself. Notes always go.

Until the public release of Relay Everything, version 1 can still change in any way, such as a field that gets a new name. After the public release, version 1 only gets additions, and a change that breaks a receiver gets a new `version`.

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
  audio bytea,
  edited_at timestamptz
);
CREATE TABLE relay_note_attachments (
  id text PRIMARY KEY,
  note_id uuid NOT NULL REFERENCES relay_notes (id),
  name text NOT NULL,
  content_type text NOT NULL,
  size bigint NOT NULL
);
CREATE TABLE relay_note_files (
  id text PRIMARY KEY,
  note_id uuid NOT NULL REFERENCES relay_notes (id),
  name text NOT NULL,
  content_type text NOT NULL,
  size bigint NOT NULL,
  bytes bytea NOT NULL
);
CREATE TABLE relay_health_samples (
  id bigint NOT NULL,
  device_id text NOT NULL,
  type text NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  value double precision NOT NULL,
  unit text NOT NULL,
  source text NOT NULL,
  PRIMARY KEY (device_id, id)
);
CREATE TABLE relay_calendar_events (
  id bigint PRIMARY KEY,
  device_id text NOT NULL,
  key text NOT NULL,
  calendar text,
  title text,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  all_day boolean NOT NULL,
  location text,
  notes text,
  url text,
  people jsonb NOT NULL,
  removed boolean NOT NULL DEFAULT false
);
CREATE TABLE relay_location_points (
  id bigint NOT NULL,
  device_id text NOT NULL,
  at timestamptz NOT NULL,
  lat double precision NOT NULL,
  lon double precision NOT NULL,
  accuracy double precision NOT NULL,
  place text,
  PRIMARY KEY (device_id, id)
);
```

Save a note with `INSERT ... ON CONFLICT (id) DO UPDATE`, and keep the stored `audio` when a `note.updated` has none. Save each of a note's `attachments` by its `id` too, and a `note.file` in `relay_note_files`. A file listed in `attachments` that has no row in `relay_note_files` did not come, such as one your receiver skipped.

## An example receiver

[`receiver.mjs`](../../webhooks/receiver.mjs) is about 80 lines of Node with no packages. It checks each signature and saves notes, their files, samples, points and calendar events in a SQLite file, so it needs no database server. It keeps a message of a type it does not know in its `other_messages` table, by its `webhook-id`, and answers `204`. It needs Node 22.13 or later.

```bash
curl -O https://relayeverything.com/webhooks/receiver.mjs
RELAY_WEBHOOK_SECRET=whsec_... PORT=8787 DATABASE=relay.sqlite node receiver.mjs
```

Your Relay Everything server, or your phone, must reach it at an `https` address. To try it from your own computer, put it behind a tunnel, such as `cloudflared tunnel --url http://localhost:8787`, and add the tunnel's address as the webhook.
