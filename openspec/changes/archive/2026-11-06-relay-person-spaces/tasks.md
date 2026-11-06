# Tasks

## 1. Phone app first (`mobile/`)

- [x] 1.1 Accept both key formats in `mobile/lib/data/api.dart` and `controller.dart`: an old Access service-token key sends `CF-Access-Client-Id`/`-Secret` as now, and a new `rek_…` key sends `Authorization: Bearer`. The QR and paste parser takes either. Add tests in `mobile/test/` for both formats and a bad one.

## 2. The spaces Worker (`app/`)

- [x] 2.1 Add `app/worker/spaces-worker.ts` with the SQLite-backed `Space` Durable Object (`query`, `batch`, `import`, `deleteEverything`, and an alarm for webhooks), and `app/wrangler.spaces.jsonc` with production, `staging` and `local` envs and a `new_sqlite_classes` migration, as `wrangler.line.jsonc` does.
- [x] 2.2 Add `schema/space-migrations/0001_relay.sql` holding today's `relay_*` schema (tables, indexes, triggers), run under `blockConcurrencyWhile` and tracked in `space_migrations`. Add a test that a new space ends with the same schema as D1 after `schema/migrations/*relay*.sql`.
- [x] 2.3 Bind `SPACES` by `script_name` in `app/wrangler.jsonc` (all envs), `app/wrangler.relay-mcp.jsonc` and `self-host/wrangler.template.jsonc` / `mcp.template.jsonc`. Extend `self-host/bindings.test.mjs` so it fails without the binding.

## 3. Directory and sign-in (`app/worker/apps/relay/`, `schema/migrations/`)

- [x] 3.1 Add the D1 migration for `relay_people`, `relay_logins`, `relay_sessions`, `relay_sign_in_codes` and `relay_keys` (design decision 5).
- [x] 3.2 Add `sign-in/` routes: email code (sent by a `send_email` binding to Cloudflare Email Service, bound in `app/wrangler.jsonc` production and staging, 6 digits, 10 minutes, 5 tries, rate limits per email and IP), Apple and Google OIDC with PKCE and `state`, sessions in a `__Host-relay_session` cookie, sign-out, and same-origin `Origin` checks on state-changing routes. Write tests for each refusal: wrong code, expired code, too many tries, replayed code, bad `state`, an unverified email, a forged ID token, a cross-origin POST, and a signed-out session.
- [x] 3.3 Add the `access` sign-in source for self-hosts (`RELAY_SIGN_IN=access`): an Access email maps to a person, and only `WONG_OWNER_EMAIL` while `RELAY_SIGN_UP` is not `open`. Test a stranger refused and the owner admitted.

## 4. One way into a space

- [x] 4.1 Add `space.ts` with `spaceOf(env, caller)` and a `Db` that wraps the stub. Replace `session(env)` in every relay route, `queries.ts`, `place.ts`, `chat-read.ts`, `chats.ts`, `samples.ts`, `notes.ts`, `pebble.ts`, `timeline.ts`, `summary.ts`, `audio.ts` and `webhooks/*` with the caller's space.
- [x] 4.2 Write `space-access.test.ts`: it fails when any worker file but `space.ts` names `SPACES.` or `idFromName`. Add route tests where Ana's session, key and AI grant each read or write only Ana's rows, with Ben's ids in the request.
- [x] 4.3 Move recordings to `people/<person id>/…` and seal them with the space's file key (design decision 10) in `notes.ts`, `pebble.ts` and `audio.ts`, through `space.ts` alone. Test that a note id from Ben's space gives Ana a 404, that a stored object is not the plain audio, that an object copied to another name fails to open, and that `space-access.test.ts` fails when another file names `RELAY_BUCKET`.

## 5. Device keys

- [x] 5.1 Rewrite `device.ts` to check `Authorization: Bearer rek_…` against `relay_keys`, keeping `reaches` and its refusals. Add page routes to make (shown once), list and turn off keys, and the Pebble address per device with its own signing secret. Keep the checker by `RELAY_CHECKER_SHA256` on staging. Update `device.test.ts` and `pebble.test.ts`.
- [x] 5.2 Add *Add a device* (QR shown once), the device list and *Turn off* to the page in `app/src/apps/relay/`, with tests.

## 6. Webhooks and the AI connector

- [x] 6.1 Carry `personId` in queue messages, and open the space in the consumer. Replace the cron sweep with each space's alarm. Update `webhooks/*.test.ts`, including a test that Ben's note never reaches Ana's webhook.
- [x] 6.2 Point `relay-mcp` sign-in at the server's sign-in (single-use code over the service binding), put `personId` in grant props, and read through `spaceOf` in `tools.ts`. Scope `ai-apps.ts` to the caller's grants. Update `auth.test.ts`, `tools.test.ts` and `ai-apps.test.ts` for two people.

## 7. Account deletion

- [x] 7.1 Add *Delete my account* (confirm by typing the email): `deleteEverything` on the space, delete the R2 prefix, keys, sessions, logins and AI grants, then the person row. Test that Ana's key, session and grant are refused after, and that Ben's data is unchanged.

## 8. Shared server, move and self-host

- [x] 8.1 Make `relay-only.ts` the shared server: no Access in front, the sign-in routes, and `app.relayeverything.com` in its Wrangler file. The company app's `/apps/relay/` redirects there.
- [x] 8.2 Write `scripts/relay-move-to-space.mjs` (paged D1 reads, the `import` RPC, R2 copy, counts per kind, `result=` line, safe to re-run), with tests on a local D1 and a local space.
- [x] 8.3 Update `self-host/setup.mjs` install and update: make `<name>-spaces`, set `RELAY_SIGN_IN=access`, make the owner's person row, and run the move on update. Update `setup.test.mjs` and `self-host/SETUP.md`.

## 9. Website and wiki

- [x] 9.1 Update `site/src/content/docs/` (`privacy.md` with who can see what and the account-owner limit, `start/install.md`, `start/connect-a-phone.md`, `start/pebble-webhook.md`, `start/run-your-own.md`, `api/keys.md`, `app/settings.md`, `connections/connect-your-ai.md`, `connections/claude-code.md`, `connections/your-database.md`). Add `start/sign-up.md` and its sidebar entry. Run `npm run relay:api-doc` in `app/`. Add the new files to `scripts/product-name.test.mjs`.
- [x] 9.2 Write `wiki/relay-spaces.md` (how a space is opened, the one-door rule and its check, the directory, the move) and link it from `wiki/README.md`. Update the device-keys line in `AGENTS.md`.

## 10. Checks and acceptance

- [x] 10.1 Run `npm test` in `app/`, `site/` and the repo root, `flutter test` in `mobile/`, `node --test self-host/*.test.mjs` and `node scripts/public-check.mjs`. All must pass.
- [x] 10.2 `/save`, then on staging: sign up two test people, send from a key each, check that neither sees the other's data on the page, through the AI connector or in webhooks, run the move on staging, and check its counts.
