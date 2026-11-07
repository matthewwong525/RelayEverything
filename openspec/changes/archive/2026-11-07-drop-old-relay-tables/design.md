## Context

See proposal.md, Why. The shared D1 database (`relay-everything-db`, `relay-everything-db-staging`, a self-host's `<name>-db`) still has the 10 pre-spaces tables: `relay_devices`, `relay_notes`, `relay_health`, `relay_locations`, `relay_chats`, `relay_chat_messages`, `relay_chat_saves`, `relay_outbox`, `relay_webhooks`, `relay_webhook_attempts`, plus `relay_move_tickets` from `20261107120000_relay_people.sql`. Every live route reads a person's space (`space.db`), never these tables. Only these read them:

- `scripts/relay-move-to-space.mjs`, the server's `POST /apps/relay/move` (`app/worker/apps/relay/move.ts`, wired in `app/worker/relay-only.ts`), and the space's `import`, `counts` and recording-adopt calls (`app/worker/spaces-worker.ts`, `app/worker/apps/relay/space.ts`: `MOVED`, `Moved`, caller kind `move`).
- `self-host/setup.mjs update`, which calls `moveToSpace` after its deploy.
- `scripts/relay-device-key.mjs`, which writes `relay_devices` and the Access "Relay devices" policy for a self-host that has not updated.
- The old `relay-ring-mcp` Workers, which run pre-spaces code. They are deleted by hand before this change (see Migration Plan).

Row counts on 2026-11-07: live 2 `relay_devices`, all else 0; staging holds test rows in each table.

## Goals / Non-Goals

**Goals:** drop the tables everywhere through the normal migration path; remove every piece of code and doc that exists only to read them or to make old Access device keys.

**Non-Goals:** the space schema (its `relay_devices.token_client_id`/`token_id` columns stay); the old unsealed recording folder in R2; the `relay-ring` forwarder; the self-host's Access app names (fact #147); the phone app's acceptance of the old key format.

## Decisions

- **A plain migration in `schema/migrations/`, not a guarded command.** The owner chose a hard remove: no one runs a self-host yet. The migration applies on staging at preview and on live at publish, as every D1 change does. Alternative: a command that drops only after the counts match. Rejected by the owner as unneeded.
- **Drop order follows the foreign keys**: `relay_webhook_attempts`, `relay_webhooks`, `relay_outbox`, `relay_chat_saves`, `relay_chat_messages`, `relay_chats`, `relay_locations`, `relay_health`, `relay_notes`, `relay_devices`, then `relay_move_tickets`. Each `DROP TABLE IF EXISTS`, so a database that never had one still applies. A child goes before its parent, so D1's foreign-key check never sees an orphan.
- **Remove the move whole**, not leave it dormant: with no old tables, its door and RPCs can only fail. The `move` caller kind, `MoveEnv`, the `/apps/relay/move` route, the self-host keys app's `/apps/relay/move` destination and the update's move step go with it.
- **Remove `scripts/relay-device-key.mjs`.** A self-host on spaces already makes keys on the page; the script writes a table that no longer exists. `scripts/check-private-access.mjs` drops its `RELAY_DEVICES` allowance, so a leftover "Relay devices" policy shows up as an extra policy.

## Risks / Trade-offs

- [A self-host from before spaces loses its old data on update] → Accepted by the owner; the spec now says so.
- [`check-private-access` flags the live app while the "Relay devices" policy still exists] → The hand to-do removes the policy before this change builds.
- [A test or the miniflare setup still seeds the old tables] → `scripts/lib-miniflare.mjs` and `app/tests/runtime/setup.ts` apply all migrations; tests that wrote old tables (`move.test.ts`, the two script tests) go with their code.

## Migration Plan

1. Before the build, by hand and each confirmed: delete the "Relay devices" policy and its token on the company app; delete the Access for SaaS apps `relay-everything AI connector` and its staging copy, and the `ACCESS_*` secrets on `relay-everything-mcp` and its staging Worker; delete the `relay-ring AI connector` apps and the `relay-ring-mcp` Workers.
2. The preview applies the migration to `relay-everything-db-staging`.
3. Publish applies it to `relay-everything-db`.

Rollback: none for the data. The code can go back, but the tables come back empty.
