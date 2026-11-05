# Keep the Relay login address on

**Status:** ready-to-ship
**Branch:** relay-status-next-steps
**Open questions:** none

## Why

Since the move to app.relayeverything.com, each sign-in to the Relay site ends on a Cloudflare page that says *There is nothing here yet*. The login sends you back to the site's first address, `relay-everything.matthewwong525.workers.dev`, and the move turned that address off. The address was turned on again by hand on 2026-11-05, but the next publish turns it off again.

## What Changes

- **Signing in always finishes.** After you sign in, you land on your Relay site, not on a dead page. This is true in the browser and for the sign-in that this computer's tools use.
  ```mermaid
  flowchart LR
    A["Sign in"] --> B["First address"]
    B -->|"today, after a publish"| C["Nothing here yet"]
    B -->|"after this change"| D["Your Relay site"]
  ```
- **Each publish keeps the first address on.** The site's settings say to keep it on, so a publish no longer turns it off.
- **The check before a publish catches it.** If a site with its own domain does not keep its first address on, the publish stops and says why. The check names the setting to add.
- **The wiki says it once.** The page on moving a Worker to a new name gets one line: when a site gets its own domain, keep its first address on, or the sign-in breaks.

Non-goals: moving the login to app.relayeverything.com as its main address, or changing who can sign in.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **Your sign-in on this computer**: Ready, done on 2026-11-05, good for 30 days.

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-server-address`: adds that a sign-in at app.relayeverything.com finishes on the site, after every publish.

## Impact

- Changed: `app/wrangler.jsonc` (top-level `"workers_dev": true`), `scripts/lib-access-config.mjs` (`privateDeployment` refuses a private deployment with routes and no `workers_dev: true`) and its test (now in the `npm test` chain in `app/package.json`), `wiki/stack/move-cloudflare-data.md` (one line).
- `scripts/lib-access-config.mjs` is a WongStack file: the check is also worth sending upstream by hand ([contributing](../../../wiki/contributing.md)).

## Decision log

- **2026-11-05** — Asked whether to turn the address on now by hand and also fix it in the settings → chose both.
- **2026-11-05** — Assumed: keep the workers.dev address as the login's main address, not move the login to app.relayeverything.com, because the publish check requires the login's main address to be the workers.dev address, and the fix is one line.
- **2026-11-05** — Assumed: the check reads the settings file before a publish, not Cloudflare after it, because it then stops a bad publish before it turns the address off.
- **2026-11-05** — Assumed: no Relay website page changes, because the change only fixes publish settings and changes nothing a person sees on the site.
- **2026-11-05** — Assumed: add the access-config tests to the `npm test` chain, because the review found CI never ran them, so the new check could be dropped with CI still passing.
- **2026-11-05** — Assumed: move the after-publish check from the tasks to the design's Migration Plan, because it can only run once the change is live, and the ship runs it then.
- **2026-11-05** — Archive checkpoint: built, reviewed (one gap fixed: the access tests now run in CI), and archived for the ship.
- **2026-11-05** — Check: `app/package.json` changes the `npm test` chain only to add `../scripts/check-private-access.test.mjs`, because CI never ran those tests; no check is loosened.
