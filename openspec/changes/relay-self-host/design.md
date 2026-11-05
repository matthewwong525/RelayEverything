# Design

## Context

Relay's server is the `relay` mini app inside the WongStack app Worker: routes in `app/worker/apps/relay/` (registered by `api.ts`, contract from `app/worker/api/contract.ts`), the page in `app/src/apps/relay/`, tables in `schema/migrations/`, bindings `DB`, `RELAY_BUCKET`, the `RELAY_WEBHOOKS` queue with its consumer, a 15-minute cron and the `RELAY_MCP` service in `app/wrangler.jsonc`, for the `relay-everything` Worker at `app.relayeverything.com`. `app/worker/index.ts` verifies the Access identity (`access.ts`), runs `deviceGate` (`apps/relay/device.ts`), then routes `/apps/<name>/api/*` through `handleApp`. Device keys are Access service tokens made by `scripts/relay-device-key.mjs`, which reads the deployment from `app/wrangler.jsonc` and `lib-access-config.mjs`; the connect code is `{"relay":1,"server","clientId","clientSecret"}`.

Before this change, a phone key reached `pebble|notes|health|locations|timeline|audio`, and the plugin's chat key (`relay_devices.reaches = 'chats'`) only `POST chats|chat-saves`. The phone app reads `GET timeline` to check a key on connect (`mobile/lib/controller.dart`) and to show ring notes, and `GET audio` to play recordings.

The repo is public (b355538, `wiki/open-source.md`). Live before this build: the rename to `relay-everything` (#8), webhooks with the `relay-everything-webhooks` queue and its consumer (#5), the `relay-everything-mcp` connector in `app/worker/relay-mcp/` (#3), the plugin's send-only chat keys (#6, #7), and offline notes (#2).

## Goals / Non-Goals

**Goals:** a Relay-only Worker built from the same files as Matthew's; an AI guide over a deterministic setup script; send-only device keys everywhere; a key check with no data; the phone without server reads; docs.

**Non-Goals:** a second copy of Relay's code, WongStack's sign-in screens, employee access, memory or knowledge in an install; previews of an install; a hosted Relay for others; data moves between servers.

## Decisions

### One code, two entries

`app/worker/relay-only.ts` is a second Worker entry. It verifies the Access identity with `access.ts`, runs `deviceGate`, serves `/apps/relay/api/*` through the same contract `dispatch` that `handleApp` uses, with the `relay` app's mapping, and answers every other API path with 404 and every page path from the Relay-only assets, with `/` redirecting to `/apps/relay/`. Its `scheduled` runs Relay's sweep, and its `queue` hands every batch to the webhooks' consumer, since an install's one queue carries its own name. The AI connector is its own Worker, as on Matthew's server.

`npm run build:relay-only` (`vite build --mode relay-only`) builds both into `app/dist-relay/`: the same `index.html` with `src/relay-only.tsx` as its script, a small shell that mounts `app/src/apps/relay/App.tsx`, and none of the WongStack shell. The Worker goes through Vite too, because the shared contract finds the apps with `import.meta.glob`. The build reads `RELAY_CONFIG`, the install's filled config, and the committed template stands in for a check's build.

Why not copy `apps/relay/` into a `relay-server/` folder: two copies go stale, and every later Relay change would land twice. Why not deploy the whole WongStack app with features off: the install would then carry WongStack's routes, tables and paid-plan needs, against the request.

The contract's `authorizeRequest` consults WongStack's employee policy. An install sets `WONG_OWNER_EMAIL` and applies every migration, so the access tables are there and empty, and the policy reads `not_started`, which lets the signed-in owner in. No injected policy is needed. `worker/relay-only.test.ts` proves it through the entry: the owner reads, a phone key adds and checks itself, and the phone's read is refused.

### The install's settings

`self-host/wrangler.template.jsonc` names the entry, `migrations_dir: "../schema/migrations"`, the Relay bindings, and stand-in names and IDs that wrangler accepts. `self-host/mcp.template.jsonc` is the connector's. `setup.mjs install` fills both with the install's names, IDs, owner (`WONG_OWNER_EMAIL`) and Access team and audience, and writes `self-host/wrangler.jsonc` and `self-host/wrangler.mcp.jsonc`, both git-ignored. Neither holds a secret.

`self-host/bindings.test.mjs` lists every binding, queue consumer and cron in `app/wrangler.jsonc` and fails when the template lacks one, naming it. Matthew's other bindings (`MEMORY_*`, `LIVE_LINE`, `ARTIFACTS`) are WongStack's, so the test ignores them, and fails if the template has one. The connector's template must match `app/wrangler.relay-mcp.jsonc`. `app/`'s `npm test` runs it.

Migrations: the install applies every file in `schema/migrations/`, WongStack's tables too, because the files are one ordered folder and splitting it breaks Matthew's history. The unused tables are empty and cost nothing. A test fails if a Relay migration depends on a WongStack row.

### The setup script and the guide

`self-host/setup.mjs` is plain Node 20+, no packages, calling Cloudflare's API with the person's token and `npx wrangler` from `app/`:

| Command | Does |
|---|---|
| `check` | reads the token's permissions and the account; prints each missing permission; makes nothing |
| `install --email <you> [--name relay]` | runs `check`; makes the D1 database, R2 bucket and queue, an Access app on the Worker's `workers.dev` address with an owner policy for the email; writes the configs; applies migrations; deploys the connector, then the server; makes the Pebble signing secret and the connector's Access for SaaS sign-in; prints `server=` and `connector=`. The first device key adds the *Relay devices* policy. |
| `update` | builds, applies new migrations, then deploys; a failed migration stops before the deploy |
| `status` | prints the address, the parts, and whether each answers |
| `remove [--yes]` | lists what it would delete, and deletes only with `--yes`: both Access apps and their device keys, both Workers, the sign-in store, the queue, the database, and the bucket after its objects; this can't be undone |

Each command prints `result=ok|refused|failed` and key-free lines. The script never prints a token or secret; the Pebble secret goes on a private page under `~/.relay-everything/self-host/`, like device keys.

`self-host/SETUP.md` is what the AI reads. It says what will be made and asks before `install`; sends the person to Cloudflare's token page with the permission list (and a prefilled link if Cloudflare's page takes one, checked at build); has them paste the token into a git-ignored `self-host/.env`, never into chat; runs `check`, then `install`; then has them make each key. It also holds *update my Relay* (`git pull`, then `update`) and *remove my Relay*. It names no WongStack skill.

Why a script under the guide, not the guide alone: the same calls repeat for every person, and a script runs them the same way and is tested ([the principles](../../../wiki/agent-knowledge-center.md#most-process-improvements-shouldnt-use-ai)).

Access in the person's account: Zero Trust's free plan, its team domain picked or made by `install`. Why Access over the install's own keys: the page needs a login anyway, the apps and key command already speak Access, and one model keeps one set of tests.

### Device keys: send-only

`device.ts` keeps the plugin's `reaches` model, not a copy: each reach lists its adding routes, `phone` now `POST pebble|notes|health|locations` and `chats` still `POST chats|chat-saves`, and every reach may `GET key`. The gate checks the method, so a `GET` on an adding path is refused. `GET timeline`, `GET audio` and `GET summary` need a signed-in person.

`GET key` (`apps/relay/key.ts`) answers `{ device: <name> }` for an unrevoked device and 403 otherwise. It is a described contract route, so the API reference lists it.

`scripts/relay-device-key.mjs` takes its deployment from `self-host/wrangler.jsonc` when that file is there, else from `app/wrangler.jsonc` as now. `--staging` is refused on an install. The connect code is unchanged.

### The phone

After the offline change, the phone's list reads its own store. This change removes the server timeline pull and the cache of server notes, and the audio player for server recordings. Connect checks the key with `GET key`. The list gets a card, *Ring notes and recordings are on your Relay page*, with *Open your Relay page*, which opens `<server>/apps/relay/` in the system browser; it shows only while sending is on. A note's line shows *Sent* or *Waiting to send* from the outbox.

### Website and docs

New `site/src/content/docs/start/run-your-own.md`, first in *Start* after *What you need*. Changed: `what-you-need.md` (a server is your own, linked), `connect-a-phone.md` (keys from your copy of Relay; the phone checks the key), `api/keys.md` (what a device key reaches), `api/recordings.md` (only a signed-in person plays one), `app/your-notes.md`, `privacy.md`, `index.mdx` (a line and link), and the API reference by `npm run relay:api-doc`. The docs write `<your-relay-server>` for any address.

## UX

### Use-case brief
A person who wants their notes, health, places and AI chats in their own account, comfortable pasting a request into a coding AI but not with Cloudflare. Done is a working address, a login that is their email, and a phone that sends. Install is once; update is every few weeks; making a key is once per device. Edge cases: a token with missing permissions, a Zero Trust account not set up, an update whose database change fails.

### Flow
Install: website → *Run your own Relay server* → copy the request → paste in their AI → make a Cloudflare token → AI installs → make the phone's key → scan in the app. Reading: phone → *Open your Relay page* → sign in. Update: ask *update my Relay*.

### Hierarchy
Phone list: the person's own notes are the content; the Relay page card sits on top, quiet, with a ghost button; *New note* stays the main action. The website page leads with the request to copy, then cost and time, then what you get.

### Review
[review.html](review.html) sketches the phone list (What Changes item 5) and the website page (item 7). The phone app is Flutter, which this site can't run, so it is a sketch; the website page is a sketch of a Starlight page.

### Components
Phone: the existing list and card widgets in `mobile/lib/screens/timeline.dart`. Website: Starlight's own Markdown, an `:::note` and a code block.

## Risks / Trade-offs

- [Zero Trust's first setup, or turning on R2, can ask for a payment card, even on the free plan] → `check` finds a part turned off and names it; the guide and the website say so before the person starts.
- [The contract needs more of WongStack than one policy] → the fallback dispatcher in *One code, two entries*; the relay tests run against both entries.
- [An older phone app reads a refused timeline as a broken key] → Matthew is the only person with the app; he installs the new build from the same publish. The new app never calls the timeline.
- [An install falls behind and a later migration assumes newer code] → `update` applies migrations in order before deploying, as Matthew's deploy does.
- [Every WongStack table lands in an install] → empty and unused; the test that no Relay migration reads WongStack rows keeps it harmless.
- [The AI connector or webhooks need a paid feature] → `check` reports it; the guide states the cost before install.

## Migration Plan

1. One publish carries the phone app without server reads, `GET key`, and send-only `DEVICE_ROUTES`. Existing keys keep sending; nothing is deleted. Matthew installs the new phone build from that publish's release.
2. Install the test copy with `setup.mjs install`, check it, then `remove` it.

Rollback: put the old `DEVICE_ROUTES` back; no data changes. An install is removed with `setup.mjs remove`, which deletes that person's data and can't be undone.
