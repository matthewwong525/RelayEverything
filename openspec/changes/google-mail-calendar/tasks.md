# Tasks

## 1. Before the build

- [x] 1.1 Confirm `relay-api-and-connector-add` is live on `main` and rebase onto it; verify `app/worker/relay-mcp/` routes `/v1/*` and grants carry `adds`
- [x] 1.2 Pick the next free space migration number after the merged `0003_*` files; verify `ls schema/space-migrations` shows no clash

## 2. Connection and the sealed sign-in

- [x] 2.1 Add the space migration for `relay_google` and `seal`/`open` in `space.ts`; verify `space-schema.test.ts` and `space-access.test.ts` pass, and a new test shows a sealed token opens only in its own space
- [x] 2.2 Write `apps/relay/google/connect.ts` (connect, callback with scope check, status, disconnect) and wire routes for session callers only; verify tests for success, cancel, a missing scope, a key caller refused, and Ana's session never reaching Ben's row
- [x] 2.3 Write `apps/relay/google/token.ts` (refresh, in-memory cache, `invalid_grant` deletes the row, revoke); verify tests with a stubbed Google token endpoint
- [x] 2.4 Make account delete revoke and remove the connection; verify `account.test.ts` covers it

## 3. The pass-through and tools

- [x] 3.1 Write `apps/relay/google/proxy.ts` (allow-list, path checks, refused permanent deletes, streamed answer, no body logging); verify tests for each refused path and a test that the module logs no body or query
- [x] 3.2 Route `/v1/google/gmail/*`, `/v1/google/calendar/*`, `/v1/google/drive/*` (and `drive/upload/*`) and `/v1/google/contacts/*` (GET only) in the connector's API for `api` keys and grants with `google`; verify tests: phone and chat keys refused, older grant told to connect again, no connection told to connect Google
- [x] 3.3 Write `relay-mcp/google-tools.ts` with the fourteen tools and their hints, register them in `tools.ts`; verify `tools.test.ts` checks each tool's request, caps and hints, and that no tool reaches a permanent delete
- [x] 3.4 Grant `google: true` at consent and update the consent words in `auth.ts`; verify `auth.test.ts`
- [x] 3.5 Add `RELAY_GOOGLE_CLIENT_ID` to `wrangler.relay-mcp.jsonc`, the secret to `relay-mcp-setup.mjs` and `.env.example`; verify `relay-mcp-setup.mjs --check` names it
- [x] 3.6 Run `npm run relay:api-doc` in `app/` so the OpenAPI file lists the four Google paths; verify `api-doc.test.ts` passes

## 4. The page

- [x] 4.1 Write `GoogleCard.tsx` (the states in design.md's UX section) and place it below the AI apps card; verify a component test for each state

## 5. Docs

- [x] 5.1 Write `site/src/content/docs/connections/google.md` (connect, warning page, the four services, tools, API paths, what is kept, disconnect) and list it in `scripts/product-name.test.mjs`; verify `node --test scripts/product-name.test.mjs`
- [x] 5.2 Update `site/src/content/docs/privacy.md` with Google's Limited Use words, and `connections/connect-your-ai.md`; verify the site builds
- [x] 5.3 Write `wiki/stack/relay-google.md` (setup, the console steps, the review) and link it from `wiki/stack/README.md` and `wiki/relay-spaces.md`; verify the wiki link check passes

## 6. Google Cloud and trial

- [ ] 6.1 (outward) In Google Cloud console, after the person's OK: add the five scopes, the live and staging return addresses, and a second client secret saved to `.env`; set the app to *In production*; verify the consent screen lists all five scopes
- [ ] 6.2 Deploy the staging spaces Worker and connector, set the secret with `relay-mcp-setup.mjs --staging`; verify on `app-staging.relayeverything.com` that the owner connects Google, an API key lists today's events, Claude's `search_email`, `search_files` and `find_contact` answer, and *Disconnect* refuses the next call
- [ ] 6.3 Run the checks: `npm test` and the type check in `app/`, `node scripts/public-check.mjs`; then `/save` and verify CI passes

## 7. After it is live

- [ ] 7.1 (outward) After the person's OK: verify relayeverything.com in Search Console, record the review video, and send Google's verification request with the scope reasons; verify Google shows the request as sent
- [ ] 7.2 (outward) The person picks and pays the security check company; record the date of the result in the wiki page
