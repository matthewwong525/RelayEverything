# Tasks

## 0. Start after the first version

- [x] 0.1 Confirm `relay-app-first-version` is published on `main` and re-read its `app/worker/apps/relay/` tables and `timeline`/`summary` answers; update design.md's tool table if a column or shape changed. Verify: `openspec list` no longer shows it as active and the relay tables exist in `schema/migrations/`.
- [x] 0.2 Run `scripts/relay-mcp-setup.mjs --check` (written in 1.3) against `CLOUDFLARE_API_TOKEN` before any other Cloudflare step; it names each missing permission. Verify: it prints `ok` for Access apps, KV and Workers scripts.

## 1. Connector Worker and sign-in

- [x] 1.1 Add `@cloudflare/workers-oauth-provider` and `@modelcontextprotocol/sdk` to `app/package.json`; add `app/wrangler.relay-mcp.jsonc` (production and `env.staging`, `workers_dev: true`, `DB`, `OAUTH_KV`, `WONG_OWNER_EMAIL`, no other binding). Verify: `npx wrangler deploy --dry-run -c wrangler.relay-mcp.jsonc` succeeds for both environments.
- [x] 1.2 Write `app/worker/relay-mcp/index.ts` and `auth.ts`: the OAuth provider, `/authorize` redirect to Access for SaaS, `/callback` with ID-token verification and the `WONG_OWNER_EMAIL` check, 1-hour access tokens. Tests in `relay-mcp/auth.test.ts`: a non-owner email is refused with no grant made, a bad ID-token signature is refused, `/mcp` with no token or a device service-token header answers 401, and the metadata endpoints answer without a token. Verify: `npm test` passes them.
- [x] 1.3 Write `scripts/relay-mcp-setup.mjs [--staging] [--check]`: makes the KV namespace, the Access for SaaS app with an owner-only policy, and puts the secrets through `wrangler secret bulk` on stdin; idempotent; prints no secret. Test the argument handling and the no-secret output in `scripts/relay-mcp-setup.test.mjs`. Verify: the tests pass and a second `--staging` run changes nothing.

## 2. Read tools

- [x] 2.1 Move or add read functions in `app/worker/apps/relay/queries.ts` (notes search, note by id, timeline page, day summary, health buckets, place visits), each capped and paged, `SELECT` only; point the app's `timeline` and `summary` routes at them. Tests in `queries.test.ts` against seed rows, including the route answers staying the same. Verify: `npm test` passes.
- [x] 2.2 Write `app/worker/relay-mcp/tools.ts`: the six tools in design.md through `createMcpHandler`, each `readOnlyHint: true`, Zod inputs with `.describe()`, Toronto days by default, no `audio_key`, `device_id` or `delivery_id` in any answer. Tests in `tools.test.ts`: `tools/list` shows six read-only tools, each tool answers on seed data, limits and ranges hold, and a check fails on any statement other than `SELECT` in `relay-mcp/` or `queries.ts`. Verify: `npm test` passes.

## 3. Connected apps on the Relay page

- [x] 3.1 Add the `Grants` RPC entrypoint (`list`, `revoke`) to the connector, the `RELAY_MCP` service binding in `app/wrangler.jsonc` (staging to staging), and the relay routes `GET ai-apps` and `POST ai-apps-disconnect`, refused to device tokens. Tests: list shows each grant's client name and time, revoke stops that token and keeps another, a device token gets 403. Verify: `npm test` passes.
- [x] 3.2 Build `app/src/apps/relay/AiCard.tsx` on the Relay page by design.md's UX: the address with *Copy*, connected apps with *Disconnect* and its confirm dialog, the empty state. Component test for the three states. Verify: `npm test` passes and the card shows on a local run.

## 4. Deploy and docs

- [x] 4.1 Add the connector's deploy step to `scripts/cf-deploy.sh` beside `wong_deploy_line`, on `main` only, before the app, whose `RELAY_MCP` binding needs it. Verify: the deploy script's existing tests pass and a dry run lists the connector.
- [x] 4.2 Write how to connect each chat app (Claude app and Desktop, ChatGPT developer mode, `claude mcp add --transport http`), how to disconnect, and what data leaves, on the Relay wiki page the first version adds, else a new page linked from [the wiki](../../../wiki/README.md). Verify: the wiki check passes.

## 5. Verify

- [x] 5.1 Before the save, run `node scripts/relay-mcp-setup.mjs --staging` twice, then `node scripts/relay-mcp-trial.mjs` (written here, with `--sign-in` if a sign-in is to hand). Verify: the second setup prints no `deployed`, `made` or `put`; the trial prints `trial: pass`: OAuth metadata, an app registers, the consent page names it, approve hands it to the Access sign-in, and a made-up sign-in answer, a made-up code, a wrong token and a service token are each refused; with `--sign-in`, the owner's sign-in gives a token that reads the made-up note *Buy milk and batteries.*
- [x] 5.2 Just before the merge, run `node scripts/relay-mcp-setup.mjs` for production. Verify: it prints `ok worker relay-ring-mcp`, the Access app and the secrets. (The publish's deploy is checked after the merge with `--live`.)
