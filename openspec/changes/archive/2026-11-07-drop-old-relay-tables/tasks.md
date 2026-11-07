## 1. Before the build

- [x] 1.1 Confirm the hand to-do is done: no "Relay devices" policy on the company app's Access app, no `relay-everything AI connector` or `relay-ring AI connector` Access apps, no `ACCESS_*` secrets on `relay-everything-mcp`(-staging), no `relay-ring-mcp`(-staging) Workers

## 2. Database

- [x] 2.1 Add a migration in `schema/migrations/` that drops the 10 old `relay_*` data tables and `relay_move_tickets`, children first, each `IF EXISTS`
- [x] 2.2 Add a test that applies every migration to an empty database and finds no old table, while `relay_people`, `relay_keys` and `relay_sessions` stay

## 3. Server and spaces

- [x] 3.1 Remove `app/worker/apps/relay/move.ts` and `move.test.ts`, the `/apps/relay/move` route and `MoveEnv` in `app/worker/relay-only.ts`, and the `move` caller kind
- [x] 3.2 Remove `MOVED`, `Moved`, `import`, `counts` and the recording-adopt call from `app/worker/apps/relay/space.ts` and `app/worker/spaces-worker.ts`; update `space-access.test.ts`, `space-schema.test.ts`, `spaces-worker.test.ts` and `relay-only.test.ts`
- [x] 3.3 Regenerate `app/worker-configuration.d.ts` if it names the removed parts

## 4. Scripts and self-host

- [x] 4.1 Remove `scripts/relay-move-to-space.mjs`, `scripts/relay-device-key.mjs` and their tests; take them off `scripts/product-name.test.mjs`'s list
- [x] 4.2 In `self-host/setup.mjs`, remove the move step from `update`, the `/apps/relay/move` destination from `keysApp`, and the "Relay devices" comment; update `self-host/setup.test.mjs`
- [x] 4.3 Remove the `RELAY_DEVICES` allowance from `scripts/check-private-access.mjs`; update its test so a "Relay devices" policy counts as an extra policy

## 5. Docs

- [x] 5.1 Update `AGENTS.md` (Device keys), `wiki/relay-spaces.md` (the move paragraph) and `self-host/SETUP.md`
- [x] 5.2 Update the site's `api/keys.md` and `start/run-your-own.md`, and run `npm run relay:api-doc` in `app/` since a route goes

## 6. Checks

- [x] 6.1 Run the app, script and self-host tests, `scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [x] 6.2 `/save`, then check the preview: the staging database lists no old table, and a phone key still sends a note to its space
