# Give each person their own locked space on Relay Everything

**Status:** ready-to-ship
**Branch:** per-user-d1-database
**Open questions:** none

## Why

Today one Relay Everything server keeps all its data in one database, with nothing to tell one person's notes from another's. That works for one owner. It does not work if other people sign up: everyone who signs in would see everyone's notes, health and places. Each person needs their own space that only they can open.

## What Changes

- **Anyone can sign up on the shared server.** They sign in with a code sent to their email, or with Apple or Google, and get their own empty space. The sign-in comes with the server, so each new person costs no login fee.
  ```screen
  <div class="card col gap phone">
    <h3>Relay Everything</h3>
    <p class="muted">Sign in or make an account</p>
    <button class="btn-ghost">Continue with Apple</button>
    <button class="btn-ghost">Continue with Google</button>
    <div class="sep"></div>
    <input class="field" placeholder="you@example.com">
    <button class="btn-primary">Email me a code</button>
    <p class="muted">New here? The same steps make your account.</p>
  </div>
  ```
  A sketch, not a prototype: this plan settles the data and safety shape. The build makes the real page.
- **Each person's data lives in their own locked space.** Their notes, health, places, chats, devices and webhooks go in a separate store that holds only their data. Recordings go in their own folder in the file store, each locked with a key kept in the person's space, so not even the Cloudflare dashboard can play them. One shared list holds only who has an account and which key belongs to whom.
  ```mermaid
  flowchart LR
    A["Ana's phone"] --> S["Server"]
    B["Ben"] --> S
    S --> SA[("Ana's space")]
    S --> SB[("Ben's space")]
    S --> L[("Accounts")]
  ```
- **Nobody can read another person's space, the owner included.** The server opens a space only for the person who is signed in, or for that person's own device key or AI app. There is no owner screen, route or tool that opens someone else's space, and a test fails if one is added. The code is public, so anyone can check this. One limit is stated on the privacy page: the owner of the Cloudflare account could change the code. Only phone-side encryption stops that, and this plan does not add it.
- **Devices get their keys from the Relay Everything page.** You tap *Add a device*, and the page shows the key once as a QR code. The phone scans it as it does now. The Pebble app and Claude Code get their keys the same way. A key only adds data to its own person's space, and you turn a key off on the page. Phones need the app update that reads the new key before the switch.
- **Your AI app sees only your space.** Any person with an account can connect Claude or ChatGPT. It signs in with the new sign-in and reads only that person's notes, health and places.
- **Webhooks belong to each person.** Each person adds their own webhooks, and each one sends only that person's data.
- **You can delete your account.** Settings has *Delete my account*. It removes your space, your recordings, your keys and your connected AI apps. This can't be undone.
- **Your current data moves into your own space.** All your notes, recordings, health, places, chats, devices and webhooks are copied into your space and counted against the old database. The old tables are emptied only after you check that everything is there. Emptying them can't be undone.
- **Running your own server stays the same for you.** A self-hosted server stores data the same way, in one space per person. It keeps its current login for the owner's email, and no one else can sign up until the owner turns sign-up on.
- **The website explains the new way.** The privacy page says who can see what, the setup pages say how to sign up and add a device, and the key and AI pages match.

Non-goals: free and paid tiers, taking payment, phone-side encryption, an owner screen that opens other people's data, and limits on how much a person stores.

## What the build needs

- **Cloudflare email sending for relayeverything.com**: Ready, turned on 2026-11-06.
- **Sign in with Apple**: Ready. App ID, Services ID and key (`RELAY_APPLE_SIGN_IN_KEY`, `RELAY_APPLE_SIGN_IN_KEY_ID`) are made, saved, and on the live app.
- **Sign in with Google**: Ready. Project `relay-everything`, its web client in production, and `RELAY_GOOGLE_SIGN_IN_SECRET` saved and on the live app.
- **The shared server's address**: Ready, `app.relayeverything.com`, with `app-staging.relayeverything.com` for previews. Both are on Apple's and Google's lists.
- **Cloudflare**: Ready, the deploy key in `.env` already makes Workers, Durable Objects and D1 databases.

## Capabilities

### New Capabilities
- `relay-person-spaces`: each person's data in their own Durable Object space, reached only by that person's session, device key or AI app grant; recordings under the person's own prefix; account deletion; moving the owner's existing data.
- `relay-sign-in`: open sign-up and sign-in on the shared server by email code, Apple or Google; server-held sessions; self-hosted servers keep Access for their owner and keep sign-up closed by default.

### Modified Capabilities
- `relay-device-keys`: keys are made and turned off on the Relay Everything page, belong to one person, and reach only that person's space; Access service tokens are no longer device keys on the shared server.
- `relay-ai-connector`: the connector admits any person with an account, not only the owner, and each grant reads only its own person's space.
- `relay-webhooks`: only the person whose space holds a webhook manages it, and it sends only that person's data.

## Impact

- New Worker `relay-everything-spaces` (`app/wrangler.spaces.jsonc`, `app/worker/spaces-worker.ts`) exporting the SQLite-backed Durable Object class `Space`, with `-staging` and `-local` twins; bound as `SPACES` by `script_name` in the app, relay-only and connector Workers, like `LIVE_LINE`.
- `app/worker/relay-only.ts` becomes the shared server's Worker on its own address, outside Access, with the sign-in routes; the company app's `/apps/relay/` sends people to it.
- `app/worker/apps/relay/**`: every route takes its database from the caller's space instead of `env.DB`; `store.ts` `session()` replaced by a space handle; `device.ts` checks server-made keys; webhooks' sweep moves to each space's alarm; `audio.ts` reads `people/<person id>/`.
- `schema/migrations/`: new directory tables in D1 (`relay_people`, `relay_sessions`, `relay_sign_in_codes`, `relay_keys`); a later migration drops the old `relay_*` data tables after the move. New `schema/space-migrations/` run inside each space.
- `app/worker/relay-mcp/**`: sign-in through the server's own sign-in; grant props carry the person id; tools read the person's space.
- `mobile/lib/data/api.dart`, `mobile/lib/controller.dart`: the new key format and `Authorization: Bearer`, accepting the old key until the switch.
- `plugin/`: the chat key from the page.
- `scripts/relay-device-key.mjs` retired for the shared server; new `scripts/relay-move-to-space.mjs` for the one-time move.
- `self-host/setup.mjs`, `self-host/wrangler.template.jsonc`, `self-host/mcp.template.jsonc`, `self-host/SETUP.md`: the spaces Worker, the owner's person row, sign-up off.
- Website: `site/src/content/docs/privacy.md`, `start/install.md`, `start/connect-a-phone.md`, `start/pebble-webhook.md`, `start/run-your-own.md`, `api/keys.md`, `app/settings.md`, `connections/connect-your-ai.md`, `connections/claude-code.md`, `connections/your-database.md`, a new `start/sign-up.md`, and `api/reference.md` from `npm run relay:api-doc`.
- Wiki: a new `wiki/relay-spaces.md`, linked from `wiki/README.md`.
- `scripts/product-name.test.mjs`: the new user-facing files join its list.

## Decision log

- **2026-11-06** — Asked whether every person gets their own D1 database → chose one Durable Object per person, each with its own SQLite, on a shared server.
- **2026-11-06** — Asked who may get a space → chose anyone can sign up; free and paid tiers come later.
- **2026-11-06** — Asked whether self-hosted servers store data the same way → chose the same per-person spaces everywhere.
- **2026-11-06** — Asked whether the owner can see other people's data → chose no: each person sees only their own.
- **2026-11-06** — Asked how locked a space is → chose no way in by design, not phone-side encryption, so search, the AI app and webhooks keep working.
- **2026-11-06** — Asked whether the owner must be unable to read people's data, even as the Cloudflare account owner → chose no: the current lock is enough, and the privacy page says the account owner could still get in.
- **2026-11-06** — Asked whether files in R2 get the same lock → chose to lock each file with a key kept in its owner's space, so the Cloudflare dashboard can't open them.
- **2026-11-06** — Asked how people sign in → chose the server's own sign-in (email code, Apple, Google), not Cloudflare Access, which costs about $7 a person after 50.
- **2026-11-06** — Asked whether the sign-in codes can go out through Cloudflare → chose Cloudflare Email Service, not Resend, so no other company holds a key.
- **2026-11-06** — Asked what the paid tier gives and whether to plan payment → chose to leave tiers and payment out of this plan.
- **2026-11-06** — Asked which Google account owns Sign in with Google → chose matthewwong525@gmail.com, in a new Google Cloud project `relay-everything`.
- **2026-11-06** — Assumed: Sign in with Apple uses its own new App ID, `com.matthewwong525.relayeverything.web`, because turning it on for the iPhone app's App ID would make its signing profiles invalid and could break the iPhone builds.
- **2026-11-06** — Assumed: staging signs in at `app-staging.relayeverything.com`, because Apple and Google accept only listed return addresses, and a per-change preview address can't be listed.
- **2026-11-06** — Assumed: the spaces live in their own Worker, bound by `script_name`, because a Worker that holds a Durable Object loses its preview links, the reason `LIVE_LINE` sits in `line-worker.ts`.
- **2026-11-06** — Assumed: the shared server runs the relay-only Worker at `app.relayeverything.com`, outside Access, because open sign-up can't sit behind the company app's Access login, and self-hosting already runs that Worker.
- **2026-11-06** — Assumed: a space is named by a random person id, not the email, so a changed email keeps its space and no email shows in a Durable Object name.
- **2026-11-06** — Assumed: a self-hosted server keeps Cloudflare Access for its owner and keeps sign-up off by default, because a personal server should not let strangers in, and Access is free for one person with no email key to set up.
- **2026-11-06** — Assumed: device keys become random keys made by the server and stored only as a SHA-256, because Access service tokens need the owner's terminal and an Access policy for each one, which open sign-up can't use.
- **2026-11-06** — Assumed: account deletion is in this plan, because the App Store requires an app that makes accounts to let people delete them.
- **2026-11-06** — Assumed: the old tables are emptied in a second step, after the owner checks the counts, because emptying them can't be undone.
- **2026-11-06** — Assumed: a test fails when any route or tool opens a space from a person id taken from the request, because *no way in by design* must hold after later changes, not only today.
- **2026-11-06** — Assumed: the Apple team ID is the secret `RELAY_APPLE_TEAM_ID`, not a Wrangler var, because `.env` holds it and the public-repo check refuses a committed copy.
- **2026-11-06** — Assumed: the Pebble address stays `POST pebble`, and the device's own key names whose space and which signing secret, so a Pebble URL holds no person id.
- **2026-11-06** — Assumed: the page draws the QR code with the small `uqr` package, because the app has no QR maker.
- **2026-11-06** — Assumed: one AI-connector sign-in flow on every server: a one-time code made by the server and redeemed from the shared database. Grants from before the change get 401, and each AI app connects again.
- **2026-11-06** — Assumed: the sign-in rate limit counts per email and per IP address, and the sender address is a Wrangler var.
- **2026-11-06** — Assumed: the `relay-pebble-signing` entry stays in the app's key list, because other tests read it; Relay Everything no longer reads a saved key.
- **2026-11-06** — Assumed: the shared server's config is `app/wrangler.relay.jsonc` (`relay-everything-server`). It shares the app's database, bucket and queue, and the app keeps the queue's one consumer.
- **2026-11-06** — Assumed: `cf-deploy.sh` deploys the spaces Worker before the connector and the app on production. The staging spaces Worker and both shared servers are deployed by hand at acceptance, because the preview deploy runs the default branch's script and the company app holds `app.relayeverything.com` until the switch.
- **2026-11-06** — Assumed: the company app's redirect from `/apps/relay/` to the shared server waits for the switch, because both use `app.relayeverything.com` today and a redirect now would loop.
- **2026-11-06** — Assumed: the Claude Code plugin takes only the new connect code, `{"relay":1,"server","key"}`, because an old Access key stops working at this change.
- **2026-11-06** — Assumed: a moved webhook starts at the end of its space's send log, so the move sends no old note again; a note whose recording is gone keeps its row with no recording, and the move counts it.
- **2026-11-06** — Assumed: a self-hosted server lets device keys and the move past its Access login through a bypass Access app on `/apps/relay/api` and `/apps/relay/move`; the Worker checks each key itself.
- **2026-11-06** — Assumed: the move's check passes when the space holds at least as many rows of each kind as the old store, not exactly as many, because the old tables stay as they were while the space grows from use, so an update run after the first move would fail.
- **2026-11-06** — Asked how to go live, since the publish moves the live app to spaces before the shared server takes `app.relayeverything.com` → chose to switch right after publish: the owner is there to move the data and rescan devices, and the live app is down for that time.
- **2026-11-06** — Assumed: the company app's staging Worker binds no `SPACES` and no longer consumes the staging webhooks queue, and its relay routes answer 503, because the preview guard refuses a preview that reaches another Worker's Durable Objects; staging acceptance runs on the staging shared server, which binds `SPACES` and consumes the queue.
- **2026-11-06** — Check: `self-host/bindings.test.mjs` no longer counts a cron as a binding the install must share with the app, because each space's alarm replaces the sweep; the test now checks that the install has no cron.
- **2026-11-06** — Check: the AI connector's SELECT-only test strips the one `DELETE` of a used connect code before it checks the rest, because redeeming a code must delete it.
- **2026-11-06** — Check: `app/worker/keys.test.ts` leaves out the four sign-in secrets (`RELAY_APPLE_SIGN_IN_KEY`, `RELAY_APPLE_SIGN_IN_KEY_ID`, `RELAY_GOOGLE_SIGN_IN_SECRET`, `RELAY_APPLE_TEAM_ID`), as it leaves out the core's own key, because only the server's sign-in reads them and no company route may list them; `relay-pebble-signing` leaves the key list, because each Pebble device now has its own secret in its space.
- **2026-11-06** — Check: `app/knip.jsonc` adds `worker/spaces-worker.ts` as an entry, because it is its own Worker's entry (`wrangler.spaces.jsonc`); `app/vitest.config.ts` and `app/vite.config.ts` load `.sql` files as text, as Wrangler's Text rule does on a deploy; no test or threshold is skipped.
- **2026-11-06** — Assumed: the staging shared server gets its own webhooks queue, `relay-everything-server-webhooks-staging`, and the company app's staging Worker keeps consuming its own, because the parity check needs staging to declare as many consumers as production.
- **2026-11-06** — Staging acceptance passed on app-staging: two people signed up by email code, each key sent a note, and neither saw the other's notes, devices or webhooks on the page, through the AI connector or in webhook sends; a cross-person id got 404; the owner signed up with Google, the move gave result=ok and a second run added nothing; a deleted account's session got 401. It found and fixed a blank page on the shared server: the sign-in read the address through the company app's router. Apple sign-in was not tried.
