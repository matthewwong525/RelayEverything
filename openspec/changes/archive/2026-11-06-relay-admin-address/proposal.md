# Put the company app at admin.relayeverything.com

**Status:** ready-to-ship
**Branch:** relay-admin-address
**Open questions:** none

## Why

Relay Everything now gives each person their own space, and anyone can sign up. That open server needs the main address, app.relayeverything.com. The company app held it until now. The address moved by hand on 2026-11-06. The repository still names the old address, so the next publish takes app.relayeverything.com back, and this computer's memory and company tools call a server that no longer answers them.

## What Changes

- **app.relayeverything.com is Relay Everything.** Anyone can open it, sign up and see their own space.
  ```mermaid
  flowchart LR
    A["app.relayeverything.com"] --> B["Relay Everything: sign up, your own space"]
    C["admin.relayeverything.com"] --> D["Company app, behind its login"]
  ```
- **admin.relayeverything.com is the company app**, behind the same login as before.
- **Each publish keeps both addresses.** The company app's settings name admin.relayeverything.com, so a publish no longer takes the open server's address.
- **This computer's memory and company tools call the company app at its new address.**

Non-goals: a redirect from old links, a sign-up link on the public website, and new device keys. Each person makes new keys on app.relayeverything.com.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **The address move**: Ready, done by hand on 2026-11-06. admin.relayeverything.com is on the company app, and app.relayeverything.com is on `relay-everything-server` with its 4 sign-in keys.

## Capabilities

### Modified Capabilities

- `relay-server-address`: the company app answers at admin.relayeverything.com; app.relayeverything.com is the open Relay Everything server.

## Impact

- `app/wrangler.jsonc` production route; comments in `app/wrangler.relay.jsonc`.
- `.agents/.wong-stack.json`: memory worker and company API origin.
- `scripts/relay-device-key.test.mjs`: the live key's default server.
- `wiki/relay-spaces.md`, `wiki/relay-website.md`.

## Decision log

**2026-11-06** — Asked where the open server and the company app go → chose "company app should be admin. and actual app and stuff should be on app.relayeverything.com".
**2026-11-06** — Assumed: the old relay-ring forwarder keeps its target, app.relayeverything.com, because old Access keys stop either way and each device gets a new key there.
**2026-11-06** — Assumed: the move to the new addresses was done by hand before this change, because the live server was down until the open server had its address.
**2026-11-06** — Archived inside `/ship`; checked live before saving: app.relayeverything.com answers the Relay Everything sign-in (email, Apple, Google), and admin.relayeverything.com sends a person with no login to the company login.
