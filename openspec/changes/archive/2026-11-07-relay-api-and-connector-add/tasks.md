# Tasks

## 1. Check the sign-in library

- [x] 1.1 Read how the installed `@cloudflare/workers-oauth-provider` handles an array `apiRoute`, a token minted with `resource` = the `/mcp` address on `/v1/`, and a token with no `resource`; write a `.scratch/` test; record the answer in design.md Decision 7 and pick the documented path for services

## 2. Tables and spaces

- [x] 2.1 Add a D1 migration in `schema/migrations/` that rebuilds `relay_keys` with `reaches IN ('phone', 'chats', 'api')`, keeping every row; test: apply all migrations with rows in the old table, compare after
- [x] 2.2 Add `schema/space-migrations/0003_…sql` that rebuilds `relay_devices` with `reaches IN ('phone', 'chats', 'api', 'app')`, keeping every row; extend `space-schema.test.ts` to build a space at 0002 with rows and run 0003
- [x] 2.3 Move the note insert, resend rule and `wake` from `notes.ts` into `apps/relay/add-note.ts`; `notes.ts` calls it; existing `api.test.ts` phone note tests still pass

## 3. Keys

- [x] 3.1 `caller.ts`: add the `api` reach (no main-server route but `GET key`) and `apiKeyCaller` that vouches only for a live `api` key; tests: an `api` key is refused on `/apps/relay/api/timeline`, a phone key is refused by `apiKeyCaller`, a revoked `api` key is refused
- [x] 3.2 `device.ts` accepts `reaches: "api"`; `Devices.tsx` adds the *API key* kind with the `curl` example and no QR code, shows *API: reads and adds notes*, and hides `app` rows; update `Devices` and `App` tests

## 4. Connector: API and add tool

- [x] 4.1 Move the tool input schemas into `relay-mcp/inputs.ts`; `tools.ts` uses them unchanged; `tools.test.ts` passes
- [x] 4.2 `relay-mcp/api.ts`: the `/v1/` routes in design.md Decision 3 and JSON errors; `api.test.ts` beside it: each route's answer equals its tool's for the same input, limits and cursors hold, Ana's caller with Ben's note id gets 404, and DELETE/PUT/PATCH get 405
- [x] 4.3 `relay-mcp/openapi.ts` (design.md Decision 3a) and `GET /v1/openapi.json` with no sign-in; `openapi.test.ts`: every `/v1/` route is in the document with its method, the document passes an OpenAPI 3.1 validator, the live copy names the Worker's origin, and the site's copy names `<your-relay-server>`
- [x] 4.4 `index.ts`: send `/v1/*` with a `rek_` key to `apiKeyCaller` then `api.ts`; any other bearer to the provider's `unwrapToken`, bound to the `/mcp` resource (design.md Decision 7: `apiRoute` stays `/mcp`); `/mcp` refuses a `rek_` key; tests for each way in and each refusal (phone key, chat key, session cookie, no token, disconnected grant)
- [x] 4.5 `add_note` tool and `POST /v1/notes` through `add-note.ts`; a grant's device row made on first add; a grant without `adds` gets 403 with the reconnect words; tests: note stored once on resend, webhook woken, old grant refused but reads work
- [x] 4.6 `auth.ts` and `env.ts`: new consent words; `/callback` puts `adds: true` and a new `deviceId` in the grant props; `Grants.revoke` sets the grant's device row `revoked_at`; update `auth.test.ts` and `space-access.test.ts` if a file list changes
- [x] 4.7 `wrangler.relay-mcp.jsonc`: add the `RELAY_WEBHOOKS` queue producer for live and staging; `scripts/relay-mcp-setup.mjs --check` passes

## 5. Docs and website

- [x] 5.1 Website: a new `site/src/content/docs/api/connect-a-service.md` (both ways in, `curl` examples, `<your-relay-server>` placeholders kept); link the OpenAPI file and `api/v1-reference.md`; update `api/keys.md`, `api/reference.md`, `connections/connect-your-ai.md` (the add tool) and `privacy.md` (the API beside the connector); extend `npm run relay:api-doc` to write `site/public/api/v1.openapi.json` and `api/v1-reference.md`, then run it in `app/`
- [x] 5.2 Wiki: `wiki/stack/relay-ai-connector.md` (the API, the add tool, old grants read-only) and `wiki/relay-spaces.md` (the `api` and `app` reaches); `scripts/product-name.test.mjs` lists the new site page
- [x] 5.3 `scripts/relay-mcp-trial.mjs`: check `/v1/` refuses no token and a phone key; with `--sign-in`, read and add a made-up note through `/v1/` and `add_note`

## 6. Checks

- [x] 6.1 Run the app tests, `scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [x] 6.2 Deploy the branch's spaces Worker and connector to staging by hand; run `node scripts/relay-mcp-trial.mjs --sign-in`; make an API key on `app-staging.relayeverything.com`, load `/v1/openapi.json` into a client (Swagger or Postman) and make one call from it, read and add a note with `curl`, then turn the key off and see it refused
- [x] 6.3 `/save`, then check the preview: *Add a device* shows *API key*, and the AI apps card shows the API line
