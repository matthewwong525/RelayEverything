# Design

## Context

The phone sends through one door, `Sender` (`mobile/lib/data/sender.dart`), which gives a `RelayApi` only while sending is on. `flush` (`mobile/lib/data/outbox.dart`) sends the `outbox` table oldest first, stops at the first item that can't go now, and drops an item the server refuses (400, 413). Each outbox row already has a `destination` column, always `relay-server` today, kept for this change.

The server's webhooks (`app/worker/apps/relay/webhooks/`) send format v1 (`format.ts`, published as `site/public/webhooks/v1.schema.json`), signed by Standard Webhooks (`sign.ts`): `webhook-id`, `webhook-timestamp`, and `webhook-signature: v1,<base64 HMAC-SHA256 of "{id}.{timestamp}.{body}">` with a `whsec_` secret. The phone already depends on `crypto` (pubspec), which gives HMAC-SHA256.

*Share to Relay Everything* (PR #35, on `main`) adds a share sheet whose Swift code sends straight to the server with the phone's key when `ShareSettings.sending` is true.

## Goals / Non-Goals

**Goals:**
- One setting picks the server or one webhook; the outbox, the rounds and the triggers stay as they are.
- The phone's messages pass the published v1 schema and the same signature check as the server's.
- No item is lost to a receiver's error.

**Non-Goals:** both places at once; several webhooks; `note.updated` from the phone; changes to the server's webhooks; self-made certificates.

## Decisions

### One sender, two clients

`Settings` gains `place`: `server` or `webhook` (default `server`, so every install keeps working). The webhook's address and secret live in `KeyVault` (secure storage), as the key does; never in the store's settings row. Webhook mode needs no `Connection`: `Sender.api` takes the place, and for `webhook` reads only the address and secret. `Sender.api` returns an `Outbound` interface with `post(route, body)` and `upload(...)`: `RelayApi` for the server, a new `WebhookClient` (`data/webhook.dart`) for the webhook. `flush` keeps one loop and one order, and asks only the item's `destination` for which client to use. A second `Sender` was the other choice; it would split the one network door the offline rule depends on.

### The phone builds v1 at send time

The outbox keeps today's neutral bodies (`notes`, `attachment`, `health`, `locations`). `WebhookClient` turns each into a v1 envelope when it sends: `notes` → `note.created` (`source: typed`, `audio: null`, place `from: phone`, `attachments` as a list), `attachment` → `note.file`, `health` → `health.samples`, `locations` → `location.points`. So switching place needs no rewrite of bodies: on a switch, the store runs `UPDATE outbox SET destination = ?` in one step.

- **Device:** `{ id: <install id>, name: <phone model> }`. The install id is a UUID made once and kept in `state`.
- **Ids:** a note keeps its `clientId`; a file its own id. Health samples and location points get integer ids from a counter in `state` when they are queued, written into the body, so a retry sends the same ids.
- **`webhook-id`:** `<install id>:<outbox row id>`, stable over retries. `timestamp` in the body is when the phone saved the item; `webhook-timestamp` is the send time.

`format.ts` adds `note.file` (`{ note_id, file: { id, name, content_type, size, base64 } }`) and widens the `device.id` and `id` descriptions to say "or the phone's own id". The server never builds `note.file`. A file up to 25 MB becomes about 33 MB of JSON; that is one request on its own.

### Same format, checked both sides

A Dart test writes one example of each message the phone builds to `mobile/test/fixtures/webhook/*.json`, with fixed times and a fixed secret, plus its headers. A worker test in `format.test.ts` parses each fixture with `message` and checks its signature with the server's own check. A format change on either side then fails a test.

### Answers

Only 2xx is sent. 413 on a `note.file` drops that file (marked sent, shown as *too large for your receiver*); 413 on anything else, and every other status, timeout or no signal, stops the round with the item kept. Settings shows the last status and time. Unlike the server mode, a 400 never drops an item: a receiver's 400 is most often its own bug, and dropping would lose data.

### Address

`https://` only, no user name or password, parsed by `Uri`. Private and home addresses are allowed: the server's private-address block (`address.ts`) protects the server, and the phone needs no such guard.

### The share sheet and Shortcuts

Shortcuts already write through the app's store, so they follow the setting. Android's share window runs the app's own controller on the same store, so it follows the setting too.

On iPhone, the card sends by itself only when `ShareSettings.sending` (the App Group's `UserDefaults` key `sending`) is true. The app writes it through `ShareGroup.setSending` (`relay/files` `setShareSettings`) from `RelayController._tellShare`. In webhook mode the app writes it as off, so the card only keeps each item in `share-inbox/<clientId>/` (`ShareInbox.swift`). The app drains that inbox on open, on each return and in the background round (`drainShareInbox`), and queues it with `send: settings.sending`, so it goes to the webhook in the next round. The app also writes a second key, `later`, true in webhook mode, so the card's last line says *Kept. It sends when you open Relay Everything.*, not *Sending is off*.

## Risks / Trade-offs

- **A receiver that refuses unknown types** breaks on `note.file`. Mitigation: only phone mode sends it, the website says so, and the example receiver handles it.
- **A failing receiver holds every later item.** The order promise needs this. Settings shows the failure so the person can fix the receiver.
- **iPhone background limits** mean data comes in groups. Same as server mode today.
- **The secret on the phone** sits in the Keychain or Keystore, as the device key does.

## UX

### Use-case brief
A person who runs their own database and wants nothing on our server. They set the webhook once on the phone, then forget it. Done looks like: every new note shows in their database within the next round. Common case: notes only. Edge cases: the receiver is down; a file is too large; they switch from the server. Set up once, checked rarely. The closest screen is today's *Connect Relay Everything* screen and the *Send to Relay Everything* switch in Settings.

### Flow
Settings → *Send my notes* on → *Where should the phone send?* → *My own webhook* → type the address → *Copy* the secret → *Send a test* → *Save* → the earlier-notes question → Settings shows *To your webhook: <host>*. Picking *Relay Everything* opens today's connect screen.

### Hierarchy
- *Where should the phone send?*: the primary action is *Save*; *Send a test* and *Copy* are secondary.
- Settings: the switch stays primary; *Webhook* and *Send a test* sit where *Server* sits today.

### Review
[review.html](review.html): the What Changes items *Settings says where the phone sends* and *Set up your webhook on the phone* sketch each screen.

### Components
Existing Flutter parts only: `SwitchListTile`, `ListTile`, `SegmentedButton` for the two places, `TextField`, `FilledButton`, `OutlinedButton`. No new component.
