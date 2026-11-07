# Remove the Pebble app sending to your server

**Status:** in-progress
**Branch:** lovely-unicorn
**Open questions:** none

## Why

The Pebble app can send each ring note to your Relay Everything server, but nobody uses it now: Matthew's ring sends straight to WongOS. A way in that no one uses still needs its own key setup, its own secret and its own pages, and it tells new people to set up something we no longer support.

## What Changes

- **The Pebble app can no longer send ring notes to your server.** Its address on the server now refuses every send and stores nothing. Phones, Claude Code and scripts send as before.
  ```mermaid
  flowchart LR
    P["Pebble app"] -.->|"removed"| S["Your server"]
    F["Phone"] --> S
    C["Claude Code"] --> S
    K["Your scripts"] --> S
  ```
- ***Add a device* no longer offers *Pebble app*.** The list keeps *Phone*, *Claude Code* and *API key*. A new phone key no longer comes with a signing secret.
  ```screen
  <div class="row gap">
    <div class="card col gap phone">
      <span class="muted">Before</span>
      <h3>Add a device</h3>
      <div class="field">Kind: Phone</div>
      <div class="col gap">
        <span>Phone</span>
        <span>Pebble app</span>
        <span>Claude Code</span>
        <span>API key</span>
      </div>
    </div>
    <div class="card col gap phone">
      <span class="muted">After</span>
      <h3>Add a device</h3>
      <div class="field">Kind: Phone</div>
      <div class="col gap">
        <span>Phone</span>
        <span>Claude Code</span>
        <span>API key</span>
      </div>
    </div>
  </div>
  ```
  This is a sketch, not a picture: the change only takes one choice out of a list, so a sketch shows all of it.
- **What you already have stays.** Ring notes already on your server keep their words, recordings and places, and still show as *Ring*. A key named *Pebble app* stays in your device list until you turn it off.
- **The stored Pebble signing secrets are deleted.** With the address gone, they protect nothing. It can't be undone.
- **A ring note no longer gets its place later from your location history.** No new ring notes arrive, so there is nothing to place. Your webhook stops getting the message that said a ring note got its place. That message stays in the published webhook format, marked as no longer sent, so a receiver you already built keeps working.
- **The website stops telling people to set up the Pebble webhook.** Its two pages go, and the steps, lists and links that name it change. The ring page says the Relay Everything ring will send through the phone app when it is ready.

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-notes`: the signed Pebble route is removed; a ring note no longer takes a place from location history.
- `relay-device-keys`: a revoked key's scenario names only phones; no key gets a Pebble signing secret.
- `relay-webhooks`: the delivery scenario uses a typed note, not a ring note.
- `relay-server-address`: the old-address scenario uses a phone send, not the Pebble webhook.
- `relay-website`: the docs no longer list a Pebble webhook page.
- `relay-chats`: the chat-key rule names only phone keys, not Pebble keys.

## Impact

- Server: `app/worker/apps/relay/` (`pebble.ts`, `signature.ts`, `place.ts` removed; `api.ts`, `caller.ts`, `device.ts`, `samples.ts`, `api-doc.ts`, `webhooks/format.ts` changed) and a new space migration that drops `relay_device_secrets` and the `note.updated` outbox trigger.
- API: `POST /apps/relay/api/pebble` is gone; `POST devices` no longer answers `pebbleSecret`. **BREAKING** for any Pebble app still set up to send.
- Web app: `app/src/apps/relay/Devices.tsx`, `Setup.tsx`.
- Phone app: one line in `mobile/lib/screens/settings.dart`, which starts a phone build.
- Website: `site/` pages and sidebar, `site/public/webhooks/v1.schema.json`, `api/reference.md` (generated).
- Docs: `AGENTS.md`, `README.md`, `self-host/SETUP.md`, `wiki/relay-website.md`, `wiki/relay-spaces.md`.
- Tests and fixtures that use a Pebble key: `app/tests/relay.ts`, `app/tests/relay-space-rows.sql`, and the relay worker and web tests that use them.

## Decision log

- **2026-11-07** — Asked whether to remove the Pebble app sending to the server → chose to remove it: Matthew said it "is not a thing anymore", and his ring sends straight to WongOS's `/api/ring`.
- **2026-11-07** — Asked whether stored ring notes go too → chose to keep them, unless Matthew says otherwise.
- **2026-11-07** — Assumed: the Pebble address answers as an address that does not exist (404), with no special message, because no one sends to it and a special answer is code kept for nobody.
- **2026-11-07** — Assumed (build): with a phone key, the old Pebble address answers 403 *A device key can only send to Relay Everything.*, not 404, because the key check runs before the route list and refuses a phone key at every address it does not reach; the router behind it answers 404. Letting unknown addresses past the key check, to answer 404, would loosen it for every address. The relay-notes scenario and tasks 1.1 and 5.2 now say so.
- **2026-11-07** — Assumed: keys named *Pebble app* stay listed and working for the other phone sends until the person turns them off, because turning keys off for people changes their data without a reason.
- **2026-11-07** — Assumed: the stored signing secrets are deleted, because they guard nothing once the route is gone and a secret kept for nothing is only a risk.
- **2026-11-07** — Assumed: placing ring notes from location history and the `note.updated` message are removed, because only Pebble ring notes arrive without a place.
- **2026-11-07** — Assumed: `note.updated` stays in webhook format v1, described as no longer sent, because taking it out of the published schema changes a format receivers already read; a message that stops is not a break.
- **2026-11-07** — Assumed: the two Pebble website pages are removed with no redirect, because the site has no redirects and nothing else should send people there.
- **2026-11-07** — Assumed: the ring page says the Relay Everything ring will send through the phone app, not in the Pebble webhook's shape, because that route is gone and the ring is not built yet.
- **2026-11-07** — Check: `app/worker/apps/relay/pebble.test.ts` is deleted, because the Pebble route it tested is removed; `api.test.ts` now checks that the old address refuses a phone key and stores nothing.
- **2026-11-07** — Check: `app/worker/apps/relay/signature.test.ts` is deleted, because the Pebble signing check it tested is removed with its route.
- **2026-11-07** — Assumed (review): `relay-chats` gets a delta so its chat-key rule stops naming a Pebble key, because the review found it would outlive the change; the Purpose lines of `relay-device-keys` and `relay-notes` keep their Pebble words, because a delta can't change a Purpose and they describe the history.
- **2026-11-07** — Built inside `/ship`: the route, secret, late place and Pebble pages are gone, and the local suite passes; saved to check the website preview and the app preview.
