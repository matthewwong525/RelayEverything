# Tasks

## 0. Start

- [x] 0.1 Merge `origin/main` and confirm the rename, `relay-webhooks`, `relay-ai-connector`, `relay-claude-plugin` and `relay-offline-by-default` are archived; re-read `app/worker/apps/relay/`, `app/worker/relay-mcp/`, `app/wrangler.jsonc` and `mobile/lib/` and note in design.md any file name that moved. Verify: `openspec list` shows none of those five open.

## 1. Send-only device keys

- [x] 1.1 Add `GET key` (`app/worker/apps/relay/key.ts`) as a described contract route answering `{ device }` for an unrevoked device, with tests for a device, a revoked key and a person. Verify: `npx vitest run worker/apps/relay` in `app/`.
- [x] 1.2 Make `DEVICE_ROUTES` the adding routes plus `GET key`, checked by method and by the plugin's `reaches`; move `GET timeline` and `GET audio` to people only. Tests: a phone key is refused on `GET timeline`, `GET audio` and `GET summary`, a `GET` on `pebble`, and still adds on each `POST`; a chats key reaches only its routes. Verify: `npx vitest run worker/apps/relay worker/index.test.ts`.
- [x] 1.3 Run `npm run relay:api-doc` in `app/` and update `site/src/content/docs/api/keys.md` to the new reach. Verify: the api-doc test passes and `api/reference.md` lists `GET key`.

## 2. The phone

- [x] 2.1 In `mobile/`, check the key with `GET key` on connect, and remove the server timeline pull, its cache and the server audio player. Tests: connect accepts a 200 from `GET key` and refuses a 403; no code path calls `timeline` or `audio`. Verify: `flutter analyze && flutter test`.
- [x] 2.2 Add the *Ring notes and recordings are on your Relay page* card with *Open your Relay page* (opens `<server>/apps/relay/`), shown only while sending is on, and *Sent* / *Waiting to send* on each note. Widget tests for both states of sending. Verify: `flutter test`.

## 3. The Relay-only Worker

- [x] 3.1 Add `app/worker/relay-only.ts` with a fixed owner policy, as in design.md; run the relay route tests against both entries with a shared test helper. If the contract needs more than the policy, write the fallback dispatcher and record it in design.md. Verify: `npx vitest run worker/apps/relay worker/relay-only.test.ts`.
- [x] 3.2 Add the Relay-only page shell `app/src/relay-only.tsx` and `vite build --mode relay-only` into `app/dist-relay/`, with `/` redirecting to `/apps/relay/`. Test that the built page holds the Relay app and no WongStack shell route. Verify: `npm run build:relay-only && npx vitest run src/relay-only.test.tsx`.
- [x] 3.3 Serve the AI connector for an install the way `relay-ai-connector` deploys it (its own Worker bound to the install, or routes in the entry); test that it reads only through `queries.ts`. Verify: the connector's tests pass against the install settings.

## 4. Setup

- [x] 4.1 Write `self-host/wrangler.template.jsonc` and `self-host/bindings.test.mjs`, which fails naming any Relay binding in `app/wrangler.jsonc` that the template lacks; add a test that no Relay migration reads a WongStack table. Git-ignore `self-host/wrangler.jsonc`, `self-host/wrangler.mcp.jsonc`, `self-host/.env` and `app/dist-relay/`. Verify: `node --test self-host/*.test.mjs`.
- [x] 4.2 Write `self-host/setup.mjs` with `check`, `install`, `update`, `status` and `remove`, each printing `result=`, never a token or secret; `remove` deletes only with `--yes`. Unit tests with a fake Cloudflare API: missing permissions refuse before anything is made; a failed migration stops `update` before the deploy; no output line holds the token. Verify: `node --test self-host/*.test.mjs`.
- [x] 4.3 Make `scripts/relay-device-key.mjs` read `self-host/wrangler.jsonc` when it exists and refuse `--staging` there; tests for both deployments. Verify: `node --test scripts/relay-device-key.test.mjs`.
- [x] 4.4 Write `self-host/SETUP.md`: what is made, the cost, the token's permissions (and a prefilled link if Cloudflare's page takes one), the token into `self-host/.env`, `check`, `install`, making keys, *update my Relay*, *remove my Relay*. Name no WongStack skill. Verify: `node scripts/public-check.mjs` prints `result=clean`.

## 5. Docs

- [x] 5.1 Add `site/src/content/docs/start/run-your-own.md` to `site/sidebar.mjs`; update `what-you-need.md`, `connect-a-phone.md`, `app/your-notes.md`, `privacy.md` and `index.mdx`, writing `<your-relay-server>` for every address. Verify: `(cd site && npm test)` and `node scripts/publish-relay-site.mjs --ref HEAD --staging` prints `result=ok`.
- [x] 5.2 Update `AGENTS.md`'s device-key line (keys only add data; installs read `self-host/wrangler.jsonc`), `README.md`'s folder table (`self-host/`), and `wiki/open-source.md` with a *Run your own server* section linking `self-host/SETUP.md`. Verify: the wiki link check in `npm test` passes.

## 6. Check

- [ ] 6.1 Run the full checks: `(cd app && npm test)`, `(cd site && npm test)`, `(cd mobile && flutter analyze && flutter test)`, `node --test self-host/*.test.mjs`, `node scripts/public-check.mjs` (`result=clean`).
- [ ] 6.2 `/save`, then make a test install in Matthew's account with `setup.mjs check` and `install --name relay-selfhost-test --email <Matthew's>`. With a device key from the command, send a typed note, check `GET key`, and confirm 403 on `GET timeline`. Then `remove --yes` and `status` shows nothing left.
- [ ] 6.3 On Matthew's preview, confirm his phone keys still send and get 403 on `GET timeline`, and the Relay page still shows every note when signed in.
- [ ] 6.4 Matthew, on his iPhone and in a browser, on a test install: sign in to its Relay page, connect the phone and send a note, send one Claude Code chat, and ask its AI connector for that note. An open thread holds this; it does not hold up the publish.
