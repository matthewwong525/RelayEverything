# Design

## Context

Relay's server is the `relay` mini app from [relay-app-first-version](../relay-app-first-version/design.md) (being built in the chat "Set up the Relay ring repo"; on branch `relay-app-first-version` once saved). It stores `relay_notes`, `relay_health` and `relay_locations` in D1 `DB` and audio in R2 `RELAY_BUCKET`, and serves `GET timeline?since=` and `GET summary?day=`. The whole site sits behind Cloudflare Access; only device service tokens get a narrow exception.

WongStack has two assistant doors today, and neither fits a chat app:

- **Company actions** ([company-api.md](../../../wiki/stack/company-api.md)) reach an assistant that runs `scripts/company-api.mjs` in this project's folder, with a `cloudflared` login. The Claude app, Claude Desktop and ChatGPT cannot run it.
- **`app/worker/api/mcp.ts` and `scripts/mcp-session.mjs`** forward *outbound* to someone else's MCP server. WongStack serves no inbound MCP server.

A chat app's custom connector needs an internet-reachable Streamable HTTP MCP endpoint with OAuth 2.1 (authorization server metadata, dynamic client registration, PKCE). Cloudflare documents this exact shape: [Secure MCP servers with Access for SaaS](https://developers.cloudflare.com/cloudflare-one/access-controls/ai-controls/saas-mcp/), with `@cloudflare/workers-oauth-provider` issuing tokens and an Access for SaaS OIDC app as the upstream login.

## Goals / Non-Goals

**Goals:** one connector URL for any MCP chat app; owner-only OAuth; read-only tools over notes, health and locations; list and revoke grants from the Relay page; a staging copy for trying it before publish.

**Non-Goals:** write tools, audio, multi-user, described company actions for this project's chats, a public or open-source server, changes to Relay's tables.

## Decisions

### A separate Worker, `relay-ring-mcp`

- `app/worker/relay-mcp/index.ts`, config `app/wrangler.relay-mcp.jsonc` beside `wrangler.line.jsonc`. Production `relay-ring-mcp`, staging `relay-ring-mcp-staging`, each on its own `workers.dev` address, with no Access wall in front: the OAuth provider is its gate, and every path but the OAuth endpoints and metadata answers 401 without a token.
- Bindings: `DB` (the same D1 as the app, staging's for staging), `OAUTH_KV` (new KV per environment), secrets `ACCESS_CLIENT_ID`, `ACCESS_CLIENT_SECRET`, `ACCESS_TOKEN_URL`, `ACCESS_AUTHORIZATION_URL`, `ACCESS_JWKS_URL`, vars `WONG_OWNER_EMAIL` and `RELAY_MCP_ADDRESS`. `OAUTH_KV` has no id in git: the first deploy, which setup runs with the user token, makes it, and later deploys keep the Worker's own. No R2, no memory, no other business key.
- Why not new public paths on the main Worker: OAuth metadata must sit at the origin root (`/.well-known/oauth-authorization-server`), so it would widen the main site's bypass list, which [cloudflare-access.md](../../../wiki/stack/cloudflare-access.md#4-bypass-the-public-surface) keeps to four reviewed routes. A separate Worker leaves the main site's Access app and deployment check unchanged.
- Deploy: on publish, `scripts/cf-deploy.sh` deploys it **before** the app, after `wong_deploy_line`: the app's `RELAY_MCP` service binding needs the connector to exist. Setup deploys each environment's connector the first time, staging before the save and production just before the merge; a preview deploys only the app.

### Sign-in: `workers-oauth-provider` over Access for SaaS

- `OAuthProvider({ apiRoute: "/mcp", apiHandler, defaultHandler, authorizeEndpoint: "/authorize", tokenEndpoint: "/token", clientRegistrationEndpoint: "/register" })`, following Cloudflare's `remote-mcp-cf-access` demo.
- `/authorize` first shows a consent page that names the AI app and where its answers go (the library's `beginConsent`/`approveConsent`, against a confused deputy), then redirects to the Access for SaaS OIDC app (`relay-ring AI connector`, staging its own), whose policy allows only `WONG_OWNER_EMAIL`. `/callback` exchanges the code, verifies the ID token against `ACCESS_JWKS_URL`, and **also** checks `email === WONG_OWNER_EMAIL` before `completeAuthorization`: two locks, so a widened Access policy still admits nobody else.
- Access token lifetime 1 hour, refresh tokens rotated. A sign-in drops after 30 days unused (`refreshTokenIdleTTL`); each refresh moves that end on, so an app in use stays connected. Grant props hold only `{ email }`.
- Device service tokens carry no OAuth token, so they are refused like any anonymous call.
- `scripts/relay-mcp-setup.mjs [--staging]` uses `CLOUDFLARE_API_TOKEN` to deploy the connector when it is missing (which makes the KV namespace), create the SaaS app and its policy, and put the secrets with `wrangler secret bulk` on stdin. It prints no secret. It first checks the token's permissions and names any missing one.

### MCP tools

Stateless Streamable HTTP via the MCP SDK's `WebStandardStreamableHTTPServerTransport`, answered as JSON (no Durable Object, no `agents` package). Every tool has `annotations: { readOnlyHint: true }`, a Zod input with a `.describe()` on each field, and a cap. Times are ISO strings; days default to `America/Toronto` with an optional `timezone`.

| Tool | Input | Returns |
|---|---|---|
| `search` | `query`, `from?`, `to?`, `source?` (ring, typed), `limit≤50`, `cursor?`, `timezone?` | `{ notes, nextCursor }`: notes whose text holds every word (`LIKE`, case-insensitive), newest first. A note is the timeline's (`id`, `source`, `text`, `recordedAt`, `device`, `audio`, `place`) plus a `title`, with `recordedAt` as local ISO text |
| `fetch` | `id`, `timezone?` | one note, `placesNearby` (visits within 30 minutes) and `day` (`steps`, `sleepMinutes`, `heartRate`, `workouts`) |
| `timeline` | `from`, `to`, `limit≤100`, `cursor?`, `timezone?` | `{ notes, nextCursor }` in the range. The cursor is the app's `next` and `nextId` joined |
| `day_summary` | `day`, `timezone?` | the app's summary for that day: `notes`, `steps`, `sleepMinutes`, `heartRate`, `workouts`, `places` (each place once) |
| `health` | `type` (steps, heart_rate, sleep, workout), `from`, `to`, `bucket` (hour, day), `timezone?` | `values`: per bucket `total` (steps, sleep minutes), `min`/`max`/`average` (heart rate) or `count`/`minutes` (workout); at most 400 buckets. Hour buckets are UTC hours |
| `places` | `from`, `to`, `limit≤200`, `timezone?` | `{ visits, next }`: each run of points at one place is a visit (`name`, `lat`, `lon`, `arrived`, `left`), oldest first |

`search` and `fetch` keep the names and shapes ChatGPT's connectors look for. The tools call read functions exported from `app/worker/apps/relay/` (`queries.ts`), which the app's `timeline` and `summary` routes also use: one query, one place. If the first version keeps that SQL inside its handlers, this change moves it out with no change to their answers. No tool returns `audio_key`, `device_id` or `delivery_id`.

### Connected apps on the Relay page

- The connector exports an RPC entrypoint `Grants extends WorkerEntrypoint` with `list()` and `revoke(grantId)`, using the provider's `listUserGrants` and `revokeGrant` for `WONG_OWNER_EMAIL`. RPC is reachable only through a service binding, never from the internet.
- `app/wrangler.jsonc` binds it as `RELAY_MCP` (`entrypoint: "Grants"`; staging binds the staging Worker). Two routes in the relay mini app: `GET ai-apps` → `{ address, apps: [{ id, name, connectedAt }] }` and `POST ai-apps-disconnect` `{ id }` (the app router matches whole routes, with no path parameter). Both admit only the owner, and answer 503 `unavailable` where `RELAY_MCP` is not bound, such as a local run. Both refuse a device service token: they sit outside the device routes the first version allows.
- `app/src/apps/relay/AiCard.tsx` renders the *Your AI* card on the Relay page.

## UX

**Brief.** Matthew wants to ask his AI about his Relay data from any chat app, on phone or desktop. Done is the AI answering from his notes after one paste and one sign-in. Connecting is rare (once per app); asking is daily, and happens in the AI app, not here.

**Shortest flow.** Relay page → *Copy* → AI app's *Add connector* → paste → sign in → ask.

**Hierarchy.** The card's one primary action is *Copy*. *Disconnect* is a ghost button per row, with a confirm dialog that says the app loses access until connected again. The card sits below the timeline: setup is rare.

**Components.** `Card`, `Input` (read-only), `Button`, `Badge`, `AlertDialog` from `app/src/components/ui/`. Empty state: *No AI app connected yet* under the address.

### Review

[review.html](review.html) sketches the card (What Changes item 4). There is no prototype: the Relay page is not on `main` yet.

## Risks / Trade-offs

- **Data leaves Cloudflare when asked.** Health and places reach the AI company in tool answers. Matthew chose this; the caps keep each answer to what the question needs, and Disconnect stops it.
- **A public sign-in surface.** The connector is open to the internet. Two owner checks, no write tool, and no binding beyond `DB` and `OAUTH_KV` limit what a flaw could reach. The `DB` binding can write, so the tool code holds `SELECT` only and a test fails on any other statement in `relay-mcp/` or `queries.ts`.
- **A core deploy edit.** `cf-deploy.sh` gains one step; a later `/wong-sync` must keep it.
- **Client support moves.** OAuth dynamic registration and remote connectors vary by app and plan; the acceptance try names which app was tried.
- **Depends on the first version.** If its tables or summary shape change before publish, the tools follow them.
