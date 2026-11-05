# Design

## Context

This change builds on `relay-app-first-version` (built in `/root/relay-ring`, branch `relay-app-first-version`, not yet on `main`). Its `mobile/` is written, with 34 tests in `test/`:

- `lib/data/store.dart`: a `drift` store for typed notes, the outbox, unsent location points and small settings.
- `lib/data/{api,connection,outbox}.dart`: every saved note goes into the outbox, which sends whenever a device key is kept and waits forever without one.
- `lib/app.dart`: `home` is `relay.connected ? <timeline> : ConnectScreen(...)`, so the app opens on the key screen.
- `lib/screens/{connect,timeline,compose,settings}.dart`: Settings has *Disconnect this phone* and the server address, both assuming a connection.
- `lib/sync/{health,location,background}.dart`: the Health and Location history switches default off and ask permission only when turned on; background health runs whenever settings hold `"health": true`, connected or not.

The server already resolves ring-note places from location history (`app/worker/apps/relay/place.ts`) and stores a typed note's pin as sent.

The webhooks plan (`relay-webhooks`, other workspace) fans out from the server after it stores a row; the MCP plan reads only the server. Both stay correct if the phone simply sends less.

## Goals / Non-Goals

**Goals:** a local-first phone app whose only network use is the opt-in Relay server; an outbox that can later name another destination.

**Non-Goals:** server changes beyond setup-dialog text; a phone-side webhook destination; encryption beyond the first version's HTTPS and secure key storage; deleting server data from the phone.

## Decisions

### One setting gates all network use

- `lib/data/settings.dart` holds `sending` (off by default), `pinNotes` (off), and `health` and `locationHistory` (both forced off while `sending` is off). Stored in the `drift` store; the key stays in `flutter_secure_storage`.
- The API client is reached only through a `Sender` that returns nothing while `sending` is off, so no screen or job can call the network on its own. A test gives the app a fake HTTP client that fails on any call and drives every screen and job with sending off.
- Alternative: a check in each caller. Rejected: one missed caller breaks the promise silently.

### Notes are local rows; the outbox is per destination

- `outbox.dart` no longer enqueues on save; a note with sending off gets no outbox row, rather than a row that waits forever.
- Notes live in the local `notes` table with `clientId`, `text`, `createdAt`, optional pin, and `sentAt`. The timeline reads this table, not the server.
- `outbox(id, destination, kind, payload, createdAt)` with `destination = 'relay-server'` today. A note enters the outbox only when written with sending on, or when the person picks *Send them*. The webhooks change can add a `webhook` destination if Matthew chooses phone-side sending.
- With sending on, the existing timeline pull merges server notes (ring notes from Pebble, notes from the other phone) into `notes` by server id and `clientId`. Turning sending off keeps them.

### The earlier-notes prompt

- Turning `sending` on (after a key is connected) counts `notes WHERE sentAt IS NULL AND no outbox row`. More than zero shows *Send your N earlier notes too?*: *Send them* enqueues them oldest first; *Only new notes* enqueues nothing and records nothing, so the next turn-on asks again.
- Turning on with no key opens the first version's `ConnectScreen` first, then continues to the prompt.
- *Disconnect this phone* and the server address move inside the sending section, shown only while a key is kept; *Disconnect* forgets the key and turns sending off.

### Turning sending off

- A confirm, then: `sending = false`, `health` and `locationHistory` off, background jobs cancelled (`workmanager` tasks, iOS background fetch, location stream and Android foreground service), and `DELETE FROM outbox WHERE kind IN ('health','location')`. Note rows in the outbox stay, so a later turn-on sends them without a second prompt.
- The key stays in secure storage. The server is not called.

### Health and location only while sending

- `lib/sync/background.dart` and the location recorder start only when `sending && health` or `sending && locationHistory`, not on the switch alone. Permissions are asked when those switches turn on, never on first open.
- The first read starts at the moment health turns on; later reads continue from the last read time, as in the first version.

### Pins without the network

- `pinNotes` takes one `geolocator` fix at save time ("when in use" permission only) and stores `lat, lon, accuracy` on the note.
- No reverse geocoding on the phone while sending is off: the timeline shows *Pinned*, and tapping opens the platform map app. With sending on, the place name comes back from the server as in the first version.

### Site and docs

- `app/src/apps/relay/` *Set up a phone* dialog: first step becomes *In the app, open Settings and turn on Send to your Relay server*.
- `mobile/README.md` states the default: Relay keeps notes on the phone; sending to a server is optional.
- `AGENTS.md` Relay section: offline by default; health and location exist only while sending.
- The public website (`site/src/content/docs/`): the home page's flow, *Connect a phone*, *Settings*, the sync mark in *Your notes* (adds *On this phone*), and *Privacy* say notes stay on the phone until sending is on.

## UX

### Use-case brief

Matthew, and anyone using the public relay-app, wants a thought saved in seconds and kept private by default. Done is the note in the timeline on this phone. Common case: typing a note with sending off, many times a day. Rare case: turning sending on or off, once or twice ever. Mirrors the first version's timeline and Settings screens.

### Flow

Open → *New note* → type → *Save*: no key and no connection on the way. Sending: Settings → *Send to your Relay server* → connect key (first time only) → *Send your N earlier notes too?* → done. Off: switch → *Stop sending?* → done.

### Hierarchy

Timeline: *New note* stays the one primary action; the header chip reads *On this phone* while sending is off and the first version's sync chip while on. Settings: no primary action; health and location switches are muted and disabled until sending is on. Prompts: the safe choice (*Send them* after the person chose to send; *Stop sending* after they chose to stop) is primary.

### Review

[review.html](review.html): What Changes items 1 (timeline), 2 (Settings), 3 (earlier-notes prompt), 4 (stop prompt).

### Components

Material 3 `ListTile` cards and `Chip` as in the first version, `SwitchListTile` with `enabled: false` for the dependent switches, and `AlertDialog` for both prompts. Nothing new.

## Risks / Trade-offs

- **Pebble ring notes need sending on.** → Said in Settings, the README and the website.
- **A package may call the network on its own** (crash reporting, analytics, fonts). → Add none; the fail-on-any-call test and an airplane-mode check on both phones catch the app's own code; `google_fonts` and similar stay out.
- **The first version opens on the key screen** (`lib/app.dart`). → Task 1.2 opens on the timeline and reaches `ConnectScreen` only from the Settings switch.
- **Turning off drops waiting health and location.** → Intended: no copy while off. Notes are never dropped.

## Migration Plan

The first version has not reached anyone yet, so no installed phone has data to move. If it ships to Matthew's phones first, an existing install with a key keeps `sending = true` on upgrade, so nothing he set up stops; a new install starts off.
