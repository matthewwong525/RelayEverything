# Design: a web API and an add tool on the connector

## Context

Each person's data lives in one SQLite-backed Durable Object, opened only through `spaceOf` in `app/worker/apps/relay/space.ts` for a vouched caller ([person spaces](../../../wiki/relay-spaces.md)). Two ways in exist today:

- **The AI connector**, Worker `relay-everything-mcp` (`app/worker/relay-mcp/`). `@cloudflare/workers-oauth-provider` runs OAuth 2.1 with dynamic client registration. Sign-in goes through the main server and a one-time code, and the grant's props carry `personId`. `/mcp` has 8 read-only tools over `queries.ts`.
- **Device keys** (`rek_…`, SHA-256 in D1 `relay_keys`) with a reach `phone` or `chats`. `caller.ts` holds each reach to its add-only routes.

A signed-in browser session is the only reader outside the connector. No script and no non-AI service can read.

## Goals / Non-goals

**Goals:** one REST API that answers what the 8 tools answer, plus *add a note*; reached by an OAuth token from the same provider, or by a new `api` key; an `add_note` MCP tool; the one-door rule unchanged.

**Non-goals:** edit or delete from outside the page; per-app health and location consent (the person chose all or nothing); a new hostname; rate limiting; adding health, places or chats through the API.

## Decisions

### 1. The API lives on the connector Worker, under `/v1/`

The connector already runs the OAuth provider and the space binding, so `/v1/*` sits beside `/mcp`. The provider can't serve `/v1/` itself (Decision 7), so `index.ts` sends `/v1/*` to the new `api.ts` router before the provider, and the provider keeps `/mcp`.

*Alternative:* put the API on the main server (`app.relayeverything.com/apps/relay/api/…`) and check OAuth tokens over the `RELAY_MCP` service binding. That puts two hosts' worth of sign-in on one route and needs a token-unwrap call per request. Rejected: one Worker that issues and checks its own tokens is simpler.

### 2. An API key is checked before the OAuth provider

`index.ts`'s `fetch` looks first. A request to `/v1/*` with `Authorization: Bearer rek_…` goes to the key path. Every other request goes to `OAuthProvider`, which would otherwise refuse a token it did not issue. The key path calls a new `apiKeyCaller(env, key)` in `caller.ts`. It reuses `keyCaller`'s lookup and vouches there, so no new file vouches. It accepts only `reaches = 'api'` and refuses a revoked key. A phone or chat key on `/v1/*` gets 403. `/mcp` never takes a `rek_` key.

`reaches` in `caller.ts` gives `api` no route on the main server. An API key sent to `/apps/relay/api/*` is refused, except `GET key`, so a script can check its key.

### 3. One query layer, two front ends

`api.ts` and `tools.ts` both call `queries.ts`, with the same limits and cursors. The tool's input schemas (zod) move to a shared `inputs.ts`, so each REST route parses the same shape from query parameters or a JSON body. One schema, so the API and the tools can't drift apart. The tool's `instructions` text stops saying "every tool only reads".

| Route | Tool | Input |
| --- | --- | --- |
| `GET /v1/notes?q=&from=&to=&source=&limit=&cursor=&timezone=` | `search` (with `q`) or `timeline` | as the tool |
| `GET /v1/notes/:id` | `fetch` | `timezone` |
| `GET /v1/days/:day` | `day_summary` | `timezone` |
| `GET /v1/health?type=&from=&to=&bucket=` | `health` | as the tool |
| `GET /v1/places?from=&to=&limit=` | `places` | as the tool |
| `GET /v1/chats?q=…` / `GET /v1/chats/:id` | `search_chats` / `read_chat` | as the tool |
| `POST /v1/notes` | `add_note` | `{ clientId, text, createdAt?, lat?, lon?, accuracy?, place? }` |
| `GET /v1/me` | none | none; answers the caller's device name, as `GET key` does |

Errors are JSON `{ error, error_description }` with 400, 401, 403 or 404.

### 3a. One OpenAPI file, made from the schemas

A new `relay-mcp/openapi.ts` builds an OpenAPI 3.1 document from `inputs.ts` and each route's output schema with `z.toJSONSchema`, as `app/worker/api/discovery.ts` does for company actions. Query routes list their fields as `parameters`; `POST /v1/notes` has a JSON `requestBody`. Two `securitySchemes` describe the ways in: `oauth2` (authorization code with PKCE, its `/authorize` and `/token` URLs, and dynamic registration at `/register` named in the description) and `apiKey`, an HTTP bearer whose format is `rek_…`. The error shape is one shared component.

- **Live:** `GET /v1/openapi.json` needs no sign-in and fills `servers` and the OAuth URLs from `RELAY_MCP_ADDRESS`'s origin.
- **Website:** `npm run relay:api-doc` writes the same document to `site/public/api/v1.openapi.json` with `servers` set to `https://<your-relay-server>`, so the site names no real address. It also writes `site/src/content/docs/api/v1-reference.md` from it, in the shape of `reference.md`. A test in `openapi.test.ts` fails when either file is stale, as `api-doc.test.ts` does for the main server's routes and `format.test.ts` for `webhooks/v1.schema.json`.
- **Valid:** the test also checks the document against the OpenAPI 3.1 schema with a dev-only validator, so a tool such as Swagger or a client generator reads it.

### 4. Adding a note: one function, three callers

The insert in `notes.ts`, with its `ON CONFLICT (device_id, client_id)` resend rule and `wake(env, space, ["notes"])`, moves into `apps/relay/add-note.ts`. `notes.ts` (phone), `POST /v1/notes` and the `add_note` tool all call it. The note's `source` stays `typed`, so the webhook v1 format is unchanged.

The connector needs a `RELAY_WEBHOOKS` queue producer binding for `wake`: the live queue on production, `relay-everything-server-webhooks-staging` on staging. The space's 15-minute alarm sweep catches a lost wake-up.

### 5. Who a note is from: one device row per caller

- **An API key** gets its device row when it is made, as other keys do, with `reaches = 'api'`.
- **A connected app** gets a device row on its first add, with `reaches = 'app'`, the client's name, and a `deviceId` made at `/callback` and kept in the grant props. The insert is `INSERT … ON CONFLICT DO NOTHING`. Disconnecting the app sets the row's `revoked_at` through the `Grants.revoke` path. The page's device list hides `app` rows, because the AI apps card lists them.

A new space migration rebuilds `relay_devices` to widen its `reaches` CHECK to `phone | chats | api | app`. A new D1 migration rebuilds `relay_keys` for `api`. SQLite can't change a CHECK in place, so both use copy-and-rename, in new numbered files.

### 6. Old grants stay read-only

`GrantProps` becomes `{ personId?: string; adds?: true; deviceId?: string }`. `/callback` sets `adds` and `deviceId` only for a consent that showed the new words. `add_note` and `POST /v1/notes` with a grant that lacks `adds` answer 403, *Connect this app again to let it add notes*. Reads work as before. The tool is listed for every grant, so the AI can explain the refusal.

### 7. Token audience

The MCP clients send RFC 8707 `resource` = the `/mcp` address. A `.scratch/oauth-audience.test.ts` run against the installed `@cloudflare/workers-oauth-provider` 1.2.4 found:

- **An array `apiRoute` can't hold `/v1/`.** The provider refuses at construction every API route outside its one resource: `["/mcp", "/v1/"]` with resource `/mcp` throws *not covered by resourceMetadata.resource*. Moving the resource to the Worker's origin would change every connected app's token target, which the proposal rules out.
- **Every token is for the `/mcp` resource.** A token request with no `resource`, or with the `/mcp` address, gets audience `/mcp`. A request naming the origin or `/v1` is refused: *The resource parameter must name exactly one configured protected resource*.

So `apiRoute` stays `"/mcp"`, and `index.ts` answers `/v1/*` before the provider. A `rek_` key goes to `apiKeyCaller`. Any other bearer goes to the provider's own `unwrapToken`, which loads the token's record, refuses an expired or revoked one, and gives the grant's props. The API takes it only when its audience is the `/mcp` resource, so a token from no other server or resource works. One connect gives an app both `/mcp` and `/v1/`. **The documented path for services:** run the same OAuth flow (dynamic registration, authorization code with PKCE) and leave out `resource`, or send the `/mcp` address.

## UX

- **Add a device** gets a fourth kind, *API key*, default name *Script*, with one line on what it reaches. After **Add**, the shown-once panel gives the key, then a `curl` example for `GET /v1/me` with the connector's address. A QR code adds nothing for a script, so this kind shows none.
- **The device list** shows an API key as *API: reads and adds notes*.
- **The consent page** words become: *It can then read your notes, health, places and saved chats, and add notes, when you ask it. It can't change or delete them.*
- **The AI apps card** gets one line under the address: *The same sign-in opens the web API*, linked to the website page.

## Risks / Trade-offs

- **A connected app can now write.** An app could flood the space with notes. Each note is capped at 20,000 characters. The person sees each app's notes by its device name and disconnects the app. Rate limits are a later change if this happens.
- **All-or-nothing health and location.** A connected third-party service reads health and places. The consent page says so in plain words, and the privacy page lists the API beside the connector.
- **Table rebuilds.** Copying `relay_keys` and each space's `relay_devices` must keep every row. The migration tests build each table at the old shape with rows, run the step, and compare.
- **Spaces deploy first.** The space migration ships in the spaces Worker before the connector and the app, as [the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order) says.

## Migration

New D1 migration and a new space migration file only; no data moves. Grants made before the change keep working read-only. Deploy order: spaces Worker, connector (with its queue producer), main app.
