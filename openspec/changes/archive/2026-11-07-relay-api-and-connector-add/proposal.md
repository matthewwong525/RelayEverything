# Let your own scripts and other apps read and add to Relay Everything

**Status:** ready-to-ship
**Branch:** durable-object-mcp-api-auth
**Open questions:** none

## Why

Today only you, signed in on the page, can read your Relay Everything data, and AI apps can only read it. Relay Everything's goal is that another service plugs in easily. So your own scripts and other apps need a way in: they read your notes, health, places and chats, and they add notes. Each one gets only your space, and you turn each one off alone.

## What Changes

- **One sign-in for every app, AI or not.** An app such as Claude, ChatGPT, or another company's service shows *Connect X to Relay Everything?*. You sign in, and the app gets a token for your space only. The AI connector uses this sign-in today. The new API uses the same one, so an app connects one time and gets both.
  ```mermaid
  sequenceDiagram
    participant A as App
    participant C as Relay Everything sign-in
    participant S as Your space
    A->>C: Connect?
    C->>A: You sign in, app gets a token
    A->>S: Read or add, with the token
    S-->>A: Only your data
  ```
- **A new API key for your own scripts.** On the page, *Add a device* gets a new kind, *API key*. It shows once, like the other keys. Your script sends it, and reads and adds as a connected app does. A phone's key and a chat key still only add.
  ```screen
  <div class="card col gap phone">
    <h3>Add a device</h3>
    <div class="field col gap"><span class="muted">Kind</span><span class="tag-outline">API key</span></div>
    <span class="muted">Phone · Pebble app · Claude Code · API key</span>
    <div class="field col gap"><span class="muted">Name</span><span>Home server</span></div>
    <span class="muted">An API key reads your notes, health, places and chats, and adds notes. It can't change or delete anything.</span>
    <div class="row gap"><span class="grow"></span><button class="btn-ghost">Cancel</button><button class="btn-primary">Add</button></div>
  </div>
  ```
  This sketch stands in for a picture: the change adds one choice and one line to the form you know.
- **A web API that answers the same questions the AI asks.** Search notes, read one note, a time range, a day's summary, health, places, and saved chats. Each answer has the same limits as the AI connector, and a way to read the next page. One new call adds a note.
  | Ask | What it gives |
  | --- | --- |
  | Search notes | Notes that hold every word, newest first |
  | One note | The note, places near it, its day's health |
  | Notes in a time range | Every note, a page at a time |
  | A day | Notes count, steps, sleep, heart rate, workouts, places |
  | Health | Steps, sleep, heart rate or workouts, per hour or day |
  | Places | Each stay, with arrival and leaving times |
  | Search chats, one chat | Saved Claude Code chats |
  | Add a note | A new typed note, sent on to your webhooks |
- **AI apps can save a note.** The AI connector gets one new tool, *add a note*. Ask Claude *save this as a note*, and the note shows on your page with the app's name as its device. No tool changes or deletes.
  ```mermaid
  flowchart TD
    A["Claude: save this"] --> B["Add a note"] --> C["Your notes, from Claude"]
    C --> D["Your webhooks"]
  ```
- **A connected app gets everything it can reach, as today.** The *Connect X?* page says plainly: the app can read your notes, health, places and chats, and add notes. You can't pick parts. An app you connected before now stays read-only until you connect it again.
  ```screen
  <div class="card col gap phone">
    <h3>Connect Claude to Relay Everything?</h3>
    <span>It can then read your notes, health, places and saved chats, and add notes, when you ask it. It can't change or delete them.</span>
    <span class="muted">Its answers go to claude.ai.</span>
    <div class="row gap"><button class="btn-primary">Connect</button><button class="btn-ghost">Cancel</button></div>
  </div>
  ```
- **An OpenAPI file describes the API.** Tools such as Postman, Swagger or a code generator read it and build a client for you. The API gives its own copy, and the website has the same file, with a reference page made from it. The file is made from the API's own rules, so it can't fall out of date: a check fails if the website's copy is old.
  ```text
  openapi: 3.1
  servers:  https://<your-relay-server>
  sign-in:  Connect X? (OAuth) or an API key
  paths:    /v1/notes, /v1/notes/{id}, /v1/days/{day},
            /v1/health, /v1/places, /v1/me,
            /v1/chats, /v1/chats/{id}
  ```
- **The website tells how to plug in.** A new page shows how to connect an app with the sign-in, how to use an API key, and each call with an example.

Non-goals: changing or deleting data from outside the page; picking health or location per app; a new web address for the connector; limits on how often a caller asks, beyond each answer's own limit.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are in `.env`.
- **Your click in the staging trial**: Ready, not needed before the build. Near the end, the trial shows a link: you click **Connect** once, and it reads and adds a made-up note.

## Capabilities

### New Capabilities

- `relay-api`: a read-and-add web API on each person's space, reached with a connected app's token or an API key.

### Modified Capabilities

- `relay-ai-connector`: the connector adds one tool that adds a note; its sign-in also opens the API; a grant from before stays read-only.
- `relay-device-keys`: a new key kind, *API key*, reads and adds notes; phone and chat keys stay add-only.

## Impact

- `app/worker/relay-mcp/`: `index.ts` routes `/v1/*` (key or OAuth token) beside `/mcp`; new `api.ts` for the REST routes; `tools.ts` gets `add_note`; `auth.ts` consent words; `env.ts` grant props gain `adds`.
- `app/worker/apps/relay/`: `queries.ts` stays read-only; a new shared `add-note.ts` holds the insert and webhook wake that `notes.ts`, the tool and the API share; `caller.ts` and `device.ts` learn the `api` reach.
- `schema/migrations/`: a new migration widens `relay_keys.reaches` to `api`. `schema/space-migrations/`: a new file widens `relay_devices.reaches` and adds a grant's device row.
- `app/src/apps/relay/Devices.tsx`: the *API key* kind.
- Docs: `site/src/content/docs/api/` (a new page and `reference.md`), `site/src/content/docs/api/keys.md`, `site/src/content/docs/connections/connect-your-ai.md`, `site/src/content/docs/privacy.md`, `wiki/stack/relay-ai-connector.md`, `wiki/relay-spaces.md`.
- OpenAPI: `site/public/api/v1.openapi.json`, written by `npm run relay:api-doc`, served live at `/v1/openapi.json`; `site/src/content/docs/api/v1-reference.md` generated from it.
- Scripts: `scripts/relay-mcp-trial.mjs` checks the API and the add tool.

## Decision log

**2026-11-07** — Asked who will call the new API → chose "Both (Recommended)": your own scripts with a key, and other apps through the same sign-in as the AI connector.
**2026-11-07** — Asked what an API or MCP caller may do → chose "Read and add (Recommended)": read, and add notes; never change or delete.
**2026-11-07** — Asked how an app gets health and location → chose "All or nothing": a connected app gets everything it can reach, as the connector does today.
**2026-11-07** — Assumed: the API lives on the connector Worker beside `/mcp`, because that Worker already runs the sign-in and checks its tokens, so one address serves both.
**2026-11-07** — Assumed: the connector keeps its current address, because a new address changes every connected app's token target; a nicer address is a later change.
**2026-11-07** — Assumed: callers add only notes, not health, places or chats, because the answer said "read and add notes", and the phone and chat keys already send the rest.
**2026-11-07** — Assumed: an app connected before this change stays read-only until it connects again, because its consent page said it can't change your data.
**2026-11-07** — Assumed: each connected app and each API key gets its own device row in the space, so an added note shows who added it and webhooks keep their message format.
**2026-11-07** — Assumed: no new rate limit, because each answer already has a size limit and only signed-in people can connect.
**2026-11-07** — Asked whether the API should have an OpenAPI spec in the docs → chose yes: a file on the website and served by the API, with a reference page made from it.
**2026-11-07** — Assumed: the website's copy names `<your-relay-server>` as its server and the live copy names its real address, because the docs never name the private site's address.
**2026-11-07** — Assumed: the provider keeps `/mcp` as its only route and resource, and the connector checks a token for `/v1/` itself through the provider's own token lookup, because the installed provider refuses `/v1/` under the `/mcp` resource and a new resource would change every connected app's token target.
**2026-11-07** — Assumed: a connected app's name and device id ride in its grant, so its first added note names the app and *Disconnect* turns its device row off.
**2026-11-07** — Assumed: the web API answers any web page's request (CORS open), because it takes only a bearer token and never a cookie, so a tool such as Swagger in a browser can call it.
**2026-11-07** — Assumed: the OpenAPI validator checks the website's copy with a made-up host in place of `<your-relay-server>`, because an OAuth address must be a URI and the placeholder is not one; the live copy is checked as served.
**2026-11-07** — Assumed: `/v1/` takes a token only with the `/mcp` audience and never one without, because the installed provider gives every token that audience, so a token with none can't come from it.
**2026-11-07** — Assumed: the space migration `0003` turns on `PRAGMA defer_foreign_keys` inside the migration's transaction to rebuild `relay_devices` under its own name; the staging check (6.2) must show a space at `0002` moves to `0003`, because node:sqlite stands in for the Durable Object's SQL in the tests.
**2026-11-07** — Assumed: the space step `0003_api_devices.sql` turns the deferred foreign-key check off at its end, because a run on the local Durable Object runtime showed the check otherwise stays deferred for the rest of that transaction.
**2026-11-07** — Checkpoint: built and reviewed (4 review findings fixed); the space step ran on the local Durable Object runtime with rows kept; the branch's spaces Worker and connector are on staging and the no-sign-in trial passes. Left: the signed-in trial and an API key on the staging server (6.2), and the preview check (6.3).
**2026-11-07** — Assumed: the D1 API keys migration runs after main's phone codes migration (`20261107210000`), because both had the same time stamp and the API keys step rebuilds a table the phone codes step does not touch.
**2026-11-07** — Assumed: 6.3 counts as seen on the staging server running this branch (the *API key* kind, the *API: reads and adds notes* line and the AI apps card's API line), because the preview runs the same build; `/verify` checks the preview again.
**2026-11-07** — Archive checkpoint: built, merged with main, and checked on staging: the signed-in trial passes, an API key read and added a note, a ready-made client read the OpenAPI file and called it, and the key was refused once turned off.
