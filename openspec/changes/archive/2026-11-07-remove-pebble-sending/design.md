# Design

## Context

See [proposal.md](proposal.md) for why. Today the Pebble path touches every layer:

- **Route.** `POST /apps/relay/api/pebble` (`app/worker/apps/relay/pebble.ts`) checks the Index webhook headers, the HMAC in `signature.ts` against the device's row in `relay_device_secrets`, stores a `source = 'ring'` note once per `X-Index-Delivery`, then calls `placeRingNotes` and wakes the webhooks. `api.ts` registers it; `caller.ts` lets a phone key reach it; `api-doc.ts` lists it in `HAND_PAGES` and calls phone keys "a phone or Pebble key".
- **Secret.** `device.ts` makes a `pebbleSecret` for **every** phone key, writes it to `relay_device_secrets` (space migration `0002_space.sql`), and answers it from `POST devices`. The web page shows it in `PebbleSteps` (`app/src/apps/relay/Setup.tsx`), picked by the *Pebble app* kind in `Devices.tsx`.
- **Late place.** `place.ts` gives a ring note with no place the nearest `relay_locations` point within 10 minutes. `pebble.ts` and the location batch in `samples.ts` call it. The `relay_outbox_note_updated` trigger (`0001_relay.sql`) logs `note.updated` when `lat` goes from null to a value; `webhooks/send.ts` sends it through `noteUpdated` in `webhooks/format.ts`.

Typed notes (`add-note.ts`, `notes.ts`) set their place on insert, so nothing else updates `lat`.

## Goals / Non-Goals

**Goals:**
- No Pebble route, kind, secret, late place or set-up text is left, in code, the website or the docs.
- Stored ring notes and their places, and every live device key, stay as they are.

**Non-Goals:**
- Removing `source = 'ring'` from the tables, the timeline, the API, the AI connector or webhook format v1: stored ring notes still need it.
- Changing the D1 `schema/migrations/`: spaces hold the live data.
- Turning off keys named *Pebble app*.
- The phone sending to the person's own webhook: the change `phone-sends-to-your-webhook` owns it, in its own workspace.

## Decisions

- **Delete the route, with no stub.** `api.ts` drops the entry, so the path gets the router's normal not-found. A 410 with a message was the other choice; it keeps code alive for a sender no one runs.
- **Drop the secrets in a new space migration.** `schema/space-migrations/0005_no_pebble.sql` drops `relay_device_secrets` and the `relay_outbox_note_updated` trigger. Space migrations run once per space, in order, so every space loses both on its next start. Leaving the table empty was the other choice: it keeps a secret column with no reader, and old rows stay readable in every space.
- **Remove late placing, keep `note.updated` in the format.** Delete `place.ts` and the location batch's call to it. `format.ts` keeps the `note.updated` envelope, with its description changed to say the server no longer sends it, and `send.ts` keeps sending any `note.updated` row already waiting in an outbox, so nothing queued before the update fails. Taking the type out of the schema was the other choice: a receiver that validates against the published schema would then see a different file for the same version.
- **Phone keys keep their reach, minus `pebble`.** `caller.ts`'s phone routes become `notes|attachments|health|locations`. `api-doc.ts` calls them "a phone key", and the `HAND_PAGES` entry goes. `device.ts` stops making the secret, and `POST devices` drops `pebbleSecret` from its answer; `Made` loses the field. The phone app and the plugin never read it.
- **Test fixtures use a second phone.** `app/tests/relay.ts` and `relay-space-rows.sql` rename the `pebble` key and *Pebble app* device to a second phone, such as *iPad*, and stop writing `relay_device_secrets`. The seed ring notes stay, as stored history.
- **The forwarder test uses `/notes`.** `scripts/relay-forward/worker.test.mjs` sends its example to `/apps/relay/api/notes` with a plain header, not `/pebble` with `X-Pebble-Signature`; the forwarder's own code is path-blind.

## Risks / Trade-offs

- [A person still has the Pebble webhook set up] → Each note fails, and the Pebble app keeps it in its Recent runs. The website's privacy and ring pages no longer promise it, and no live user is known: Matthew's ring sends to WongOS.
- [The settings line in `mobile/lib/screens/settings.dart` also changes in *phone-sends-to-your-webhook*] → Whichever lands second keeps the other's wording and only takes out the Pebble sentence. The change is one line.
- [Dropping a table in a space migration fails on an old space] → `space-schema.test.ts` runs every migration on a fresh space and on one seeded with `relay-space-rows.sql`; add a case for a space that has secret rows.

## Migration Plan

1. Publish the server and the space migration together. Each space drops the table and trigger on its next start.
2. Publish the website with `node scripts/publish-relay-site.mjs`.
3. Rollback: put the code back. A new `0006` would make the table again; old secrets are gone, so a Pebble user makes a new key.
