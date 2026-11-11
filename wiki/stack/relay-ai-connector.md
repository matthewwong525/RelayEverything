# Relay Everything's AI connector

Relay Everything's AI connector lets an AI chat app, such as the Claude app or ChatGPT, read your Relay Everything notes, health, sleep, workouts, calendar, places, saved chats and photos when you ask it a question, and add a note when you ask it to save one. It can't change or delete a note. The same Worker answers the [web API](#the-web-api) under `/v1/`, for scripts and services. It is part of [the Cloudflare stack](README.md): its own Worker, `relay-everything-mcp`, beside the main app.

| Where | Address to add |
| --- | --- |
| Live | `https://mcp.relayeverything.com` |
| Previews | `https://mcp-staging.relayeverything.com` |

The **AI apps** card at the bottom of the Relay Everything page shows the address, with a *Copy* button, and every app you connected. `/mcp` on the same host also works.

**The old addresses no longer answer.** The Worker has `workers_dev` off, so `…workers.dev/mcp` is gone. An app you connected there must connect again at the address above: each token is bound to the address it was made for.

### Why the bare address

The OAuth provider (`@cloudflare/workers-oauth-provider`) binds each token's audience to `resourceMetadata.resource` exactly. So `RELAY_MCP_ADDRESS` is the bare origin with a slash, `https://mcp.relayeverything.com/`: a resource whose path is `/` covers every path, `/mcp` and `/v1/` included. The provider's `apiRoute` stays `/mcp`, because `/` as a route would also take `/authorize` and `/callback`. So `index.ts` sends an MCP call on exactly `/` (a `POST`, a `DELETE`, a preflight, or a `GET` that accepts `text/event-stream`) to the provider as the same call on `/mcp`. A plain browser `GET /` gets a short page that names the address. The metadata is at `/.well-known/oauth-protected-resource`, with no path after it. A custom domain on a Worker comes with its deploy (`routes` with `custom_domain: true`): setup makes nothing for it.

## Connect an app

You connect each app one time. Each app opens a sign-in page: you click **Connect**, then you sign in with your Relay Everything email.

- **The Claude app** (web, desktop or phone): open **Settings → Connectors → Add custom connector**. Type `Relay Everything` as the name and paste the address. Click **Connect**, then sign in. On a new chat, turn Relay Everything on in the tools menu.
- **ChatGPT**: open **Settings → Apps & Connectors → Advanced settings** and turn on **Developer mode**. Then click **Create**, type `Relay Everything`, paste the address and pick **OAuth** for the sign-in. Click **Create**, then sign in. In a chat, pick Relay Everything from the developer-mode tools.
- **Claude Code and Codex**: use the plugin, not the connector: `/relay:connect` gives the computer its own key, which reads the same data through `/v1/` and saves chats ([Relay Everything's AI chat transcripts](relay-chats.md)). Both at once give the AI each tool two times, so `/relay:connect` names a connector it finds and its remove command.

Then ask, for example: *What did I note on 4 November?*, *How many steps did I walk last week?* or *Show me the photos from the trip to Lisbon.* Days are Toronto days unless you name another time zone.

## What the app can read and add

The connector has seventeen tools: sixteen read, and `add_note` adds. Each answer has a limit, so one question can't copy all of Relay Everything.

- **memory**: the facts in the person's memory, newest first, each with its columns, tags and sources, and the memory's columns. It finds facts by words in the text columns, a `tag` and its parts, a `source` link, a time, or a column's value in `where`. Only live facts unless `all`; a replaced fact names its replacement in `replacedBy`. The server instructions tell the AI to search the memory first for what the person decided, likes or plans ([Relay Everything's memory and knowledge web](relay-knowledge-web.md)).
- **read_fact**: one fact by its id, with the facts it replaced and the fact that replaced it.
- **search**: notes that hold every word you give, or that carry a `tag`, newest first. Give `query`, `tag` or both.
- **fetch**: one note, the places you stayed near it in time, and its day's health totals.
- **timeline**: every note from one time to another, a page at a time.
- **day_summary**: one day's notes count, health totals, the `nights` that ended that day (no stage timeline), each workout in `workouts.items`, places, trips and events (title, start, end and people's names). `places` has one row per stay (`id`, `name`, `lat`, `lon`, `from`, `to`, and `address`, `event` and `ongoing` when it has them); `trips` has each trip's `id`, `mode`, `km`, `minutes`, and the names of the stays it went `from` and `to`. A health type with no readings that day is left out.
- **health**: one type from `HEALTH_TYPES` in `queries.ts`, one value per hour or per day.
- **nights**: the nights that end from one time to another, newest first, from `relay_nights`: bed, asleep and woke times and the minutes in each stage. `stages: true` adds each night's stage timeline. Of nights that overlap, as a watch's night and the phone's bedtime, `nightPage` keeps the one with the most minutes asleep. `nextCursor` reads on.
- **workouts**: the workouts that start from one time to another, newest first, with `kind`, `minutes`, `km` and `calories`. `workoutPage` gives a workout that two phones or sources keep, starting within a minute, once, with its details when one has them. A workout from before the phone sent details has `kind` null.
- **calendar**: events from `relay_calendar_events` between two times, by start, or newest first with `q`; removed events are skipped. `GET /v1/calendar` is the same read. `fetch` stays notes and chats.
- **places**: `visits`, the stays from one time to another (`id`, name, street as `address`, the calendar `event` that named it, `lat`, `lon`, `arrived`, `left`, `minutes`, and `ongoing` while you are still there), and `trips` between them (`id`, `mode`, `km`, `minutes`, `from` and `to`), with `next` to read on. The phone works out stays and trips ([phone sync](../relay-phone-sync.md)), and the server keeps them in `relay_stays`. For points that no stay or trip covers, `placeVisits` in [`queries.ts`](../../app/worker/apps/relay/queries.ts) gives the old runs of points at one street, so old days and a phone on *Only points* answer as before; where two phones' stays overlap, it keeps the longer one, and it reads on until the page is full. A stay not sent for 6 hours reads as ended, not `ongoing`.
- **points**: the location points of one stay or trip, by its `id` from `places` or `day_summary`, which is the `relay_stays` row id, so an ongoing stay keeps it as the phone sends it again. By id it reads only the points of the phone that made that stay or trip, start to end, and to now while it is `ongoing`. Or give `from` and `to`, at most 7 days, for every phone's points. `stayPoints` and `rangePoints` in [`points.ts`](../../app/worker/apps/relay/points.ts) thin the points in one SQL statement to at most `MAX_POINTS` (500), evenly, with the first and the last, and give `total`. No points (`total: 0`) is an answer, not a refusal: the person may keep only stays and trips. `GET /v1/points` is the same read.
- **search_chats**: saved chats from Claude Code and Codex, each with its `app`, that hold every word you give, with the lines that match ([Relay Everything's AI chat transcripts](relay-chats.md)).
- **read_chat**: one saved chat, a part at a time, with the AI's saved summaries.
- **photos**: photos the phones sent, from one time to another, newest first: each one's id, time taken, place (`lat`, `lon`), width and height, with `nextCursor` for the next page. `near` (`lat`, `lon`, `km` up to 500) keeps only photos near a point; `limit` is at most 50.
- **read_photo**: one photo by its id, as an image (`image/jpeg`), plus a text line with its time and place, for an app that drops images. An unknown id is a tool error.
- **add_note**: a typed note, under the app's own device row (`reaches = 'app'`, named for the app), made on its first note. The app's `clientId` keeps a resend to one note, and the note wakes the webhooks that take notes, as a phone's does. An app connected before adding has no `adds` in its grant: it reads, and `add_note` asks it to connect again.

To read a photo, the connector binds the same file store as the app, `RELAY_BUCKET`, in each environment of `app/wrangler.relay-mcp.jsonc` and in `self-host/mcp.template.jsonc`. It opens a photo only through the space's own seal, as the page opens a recording ([recordings, note files and photos](../relay-spaces.md#recordings-note-files-and-photos)). No tool reads a recording or a note file. The web API has no photo route: `read_photo` answers an image, and `near` is no query field.

## What leaves Relay Everything

When an app uses a tool, the answer goes to that app's company: Anthropic for Claude, OpenAI for ChatGPT. Their own terms then apply to it. An answer can hold a note's words, its time, the place name and coordinates, the device name, health totals, nights of sleep with their stages, workouts, calendar events with their people, a chat's messages, and one photo with its time and place.

An answer never holds a recording, a device key, or a device's or delivery's id. The app gets only what a tool answers for one question, not a copy of the database.

## Disconnect an app

On the Relay Everything page, find the app in the **AI apps** card and click **Disconnect**, then confirm. Its sign-in stops at once: its next question gets a refusal. To use it again, connect it again from the app. You can also remove Relay Everything in the app's own settings, but that does not end the sign-in on Relay Everything's side.

## How the sign-in keeps others out

The connector has no sign-in of its own. After you click **Connect**, it sends you to the Relay Everything server named by `RELAY_SERVER_URL` in `app/wrangler.relay-mcp.jsonc`, which signs you in as it does on the page ([Relay Everything spaces](../relay-spaces.md)):

1. The server sends you back to the connector's `/callback` with a one-time code. The code works once, for a few minutes.
2. The connector trades the code in the shared database for your person id, and puts it in the grant with `adds`, a new device id and the app's name. Each tool opens only that person's space.

An app stays connected while you use it. Its access token works for one hour, and the app gets a new one when it asks again. After 30 days with no use, the sign-in drops, and you connect the app again. Disconnect ends it at once. A device key from the [Relay Everything phones](../../app/worker/apps/relay/caller.ts) can't use the connector, and the connector's tokens can't open the main app. Disconnect also turns off the app's device row.

## The web API

`/v1/` is the connector's tools as plain HTTP with JSON, for a person's own scripts and services. The website owns how to use it: [Connect a service](../../site/src/content/docs/api/connect-a-service.md). Each route parses its tool's own input from `inputs.ts` and answers through `answers.ts`, so a route and its tool can't differ; `openapi.ts` makes the OpenAPI file, served at `/v1/openapi.json` with no sign-in.

- **An API key** (`reaches = 'api'`), made with *Add an API key*, or **a computer's key** (`reaches = 'agent'`), made by `/relay:connect`, goes through `apiKeyCaller` in `caller.ts`. A phone key gets `403`; an older chat key gets `403` that says to run `/relay:connect`.
- **A connected app's token** works too. `index.ts` answers `/v1/` before the provider: it checks the token with the provider's `unwrapToken`, and its audience must name the same resource as `RELAY_MCP_ADDRESS` (`sameResource`, so a slash at the end makes no difference). A service leaves out `resource`, or sends the bare address.

A refusal answers `{ "error", "error_description" }`, and every answer is open to any web page (CORS `*`): it takes a bearer token, never a cookie. After a route change, run `npm run relay:api-doc` in `app/`: it writes the website's OpenAPI file and reference page, which name `<your-relay-server>`.

## Set it up

The setup script makes the connector's Worker and its sign-in store. The connector has no secret. Run it from the repository with the user token in `.env` ([Cloudflare credentials](cloudflare-credentials.md)):

```bash
node scripts/relay-mcp-setup.mjs --check            # the token can do each step; changes nothing
node scripts/relay-mcp-setup.mjs --staging          # the previews' connector
node scripts/relay-mcp-setup.mjs                    # the live connector
```

A second run changes nothing. When `--check` names a missing permission, widen the token as [Cloudflare credentials](cloudflare-credentials.md#how-two-permission-rows-become-enough) says, then run it again.

Deploy the spaces Worker (`app/wrangler.spaces.jsonc`), then run setup for an environment, **before** the main app deploys there. The connector binds `SPACES` and `RELAY_BUCKET`, the main app binds the connector as `RELAY_MCP`, and Cloudflare refuses a deploy whose bound Worker does not exist. For the first change that adds the connector:

1. Run setup with `--staging`, then [try it](#try-it), before the change is saved: the preview binds `relay-everything-mcp-staging`.
2. Run setup for the live connector just before the change is published: the publish deploys `relay-everything-mcp`.
3. After the publish, run the trial with `--live`.

After that, each publish deploys the live spaces Worker, then the live connector, then the main app ([`scripts/cf-deploy.sh`](../../scripts/cf-deploy.sh)). A preview deploys only the main app, and a second setup run deploys nothing. To put a branch's connector code on staging, deploy it from `app/`:

```bash
npx wrangler deploy -c wrangler.relay-mcp.jsonc --env staging
```

The sign-in store has no id in git. The first deploy, which setup runs with your token, makes it, and later deploys keep the one the Worker has. The CI deploy token can't make a store, so setup must run first.

## Try it

The trial script connects to the staging connector as an AI app does, and prints one line per check:

```bash
node scripts/relay-mcp-trial.mjs              # staging, no sign-in
node scripts/relay-mcp-trial.mjs --sign-in    # staging, then you sign in once in a browser on this computer
node scripts/relay-mcp-trial.mjs --live       # the live connector: its metadata, its page, and /, /mcp and /v1/ refused with no token
```

With no sign-in, it checks each step up to the server's sign-in: the metadata, an app's registration, the consent page, and the hand-off to the server. It also checks that a made-up sign-in answer, a made-up code, a wrong token and a service token are each refused. It can't sign in by itself. With `--sign-in`, it shows a link; you click **Connect** and sign in, and the app's token then reads a made-up note, and adds one through `add_note` and through `/v1/notes`. Disconnect the app **Relay Everything trial** on the preview's **AI apps** card after.

### On this computer

A preview has no person spaces, so a branch's new route or tool can't be tried there. Shared staging can run it only after a [staging-only deploy](../relay-spaces.md#the-workers-and-their-order), which other chats' checks share. To keep made-up data off staging, run the whole stack on this computer, each step from `app/`:

1. The spaces Worker: `npx wrangler dev -c wrangler.spaces.jsonc --env local --port 8799 --inspector-port 9341`. Each Worker needs its own inspector port: two on the same port stop with *Address already in use*.
2. The app: `npm run dev`, signed in as the [local stand-in](cloudflare-access.md#local-development). An empty local D1 has no tables, and the app answers *accounts could not be read*: first run `npx wrangler d1 migrations apply DB --local --env local`. It then has no account for the stand-in, and the app refuses it with *no account*. Add it: `npx wrangler d1 execute DB --local --env local --command "INSERT OR IGNORE INTO relay_people (id, email, created_at) VALUES ('local-dev', 'dev@example.com', 0)"`. Make a phone or API key with `POST /apps/relay/api/devices`, with the header `Origin: http://localhost:8787`: a change by cookie needs the page's own Origin.
3. The connector: copy `wrangler.relay-mcp.jsonc` to a throwaway file in `app/`, with no `env`, `RELAY_MCP_ADDRESS` and `RELAY_SERVER_URL` on `localhost`, `SPACES` and `WORKBENCHES` bound to `relay-everything-spaces-local`, the `-local` queue, and the D1 named `relay-everything-db-local`. Run `npx wrangler dev -c <that file> --port 8798`, then read `/v1/` with the API key. Delete the file after.

The page's API takes times as milliseconds since 1970; `/v1/` takes a day or an ISO time, and a note there needs its own `clientId`. A webhook can't get a message here: the sender refuses any address that is not public `https`. So read the space's `relay_outbox` rows (in `app/.wrangler/state/v3/do/`) and each webhook's `waiting` count instead. Turn each key off after.

### A computer key's route

Only `/relay:connect` makes an `agent` key, so a route that takes a computer key only, such as [the agents' database](../relay-agent-database.md), needs one made by hand. Add a test person to the database, local or staging (`--remote --env staging -c wrangler.relay.jsonc`): a `relay_people` row, a `relay_sessions` row, and a `relay_keys` row with `reaches = 'agent'`. Each row keeps its token's SHA-256 in hex. The key is `rek_` and 43 base64url characters; any other length is refused as *not one Relay Everything makes*. On staging, put the branch there first with a [staging-only deploy](../relay-spaces.md#the-workers-and-their-order), and send to `https://mcp-staging.relayeverything.com/v1/`. After, delete the person with `POST account-delete`, then delete its rows.

## Where the code is

- [`app/worker/relay-mcp/`](../../app/worker/relay-mcp/index.ts): the connector Worker, its sign-in pages, its tools and the web API.
- [`app/worker/apps/relay/queries.ts`](../../app/worker/apps/relay/queries.ts): the reads the tools and the Relay Everything page share, and [`points.ts`](../../app/worker/apps/relay/points.ts) the points read. A test fails on any statement in them but `SELECT`.
- [`app/worker/apps/relay/ai-apps.ts`](../../app/worker/apps/relay/ai-apps.ts): the routes behind the **AI apps** card.
- [`scripts/relay-mcp-setup.mjs`](../../scripts/relay-mcp-setup.mjs): setup.
- [`scripts/relay-mcp-trial.mjs`](../../scripts/relay-mcp-trial.mjs): the trial.
