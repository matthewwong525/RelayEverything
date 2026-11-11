# Design

## Context

- **A space is one Durable Object** (`Space` in `app/worker/spaces-worker.ts`) with one SQLite database. Only `apps/relay/space.ts` opens it, by RPC (`query`, `batch`). The spec says no caller makes a table or sends a database command to it.
- **The web API** (`app/worker/relay-mcp/api.ts`) answers `/v1/` on the connector Worker. Its `WEB` questions are for keys only, and `computer()` in `answers.ts` refuses all but a computer key.
- **The plugin** (`plugin/bin/relay.mjs`) calls `/v1/` with the computer's key.

## Goals / Non-Goals

**Goals:** agents on a person's computers get a free database that can't reach the space; it goes when the account goes.

**Non-Goals:** sending agent tables to webhooks, an export, or the AI connector; a screen for agent tables; reach for API keys or phones.

## Decisions

### 1. A second Durable Object class

`Workbench`, in `spaces-worker.ts`, bound as `WORKBENCHES`, one object per person, named by the person's id. Its SQLite holds only what agents make: no migration, no `relay_` table, no file key. `Space` never opens a workbench, and `Workbench` never opens a space. That is the table rule: a command naming `relay_notes` fails as "no such table", because the table is in another database.

Its RPC: `run(statements)` runs one or more statements in one transaction and answers `{ results: [{ rows, changed }] }` or `{ error }`, so a database error is the caller's answer, not a crash; `tables()` lists each table with its columns and row count; `deleteEverything()`.

### 2. Limits

A statement up to 100 KB, 50 statements a step, an answer up to 5,000 rows and 5 MB, and a database up to 1 GB. A step past a limit throws inside the transaction, so nothing it wrote stays, and the answer names the limit. Cloudflare's SQLite already refuses `ATTACH`, `BEGIN`, and some `PRAGMA`s; that error is the answer. A blob reads back as `{ "base64": … }`.

### 3. The route

`POST /v1/db` with `{ sql, params? }` or `{ batch: [{ sql, params? }] }`; `GET /v1/db/tables`. Both are `WEB` questions in `inputs.ts`, answered through `computer()`, so only a computer key gets in. A database error answers 400 with its message.

### 4. The door

`space.ts` stays the one door: `spaceOf` gains `workbench`, opened by the same checked caller, and `deleteEverything` deletes the workbench first, then the space. *Delete my account* already calls it. Every Worker that binds `SPACES` binds `WORKBENCHES` too, with the spaces Worker's script name; the spaces Worker adds migration tag `v2` with `new_sqlite_classes: ["Workbench"]`.

### 5. Kept apart

No webhook, export or the AI connector reads it, and the server puts no health or location data into it. The plugin's skill tells the AI not to copy health or places in.

### 6. The plugin

`relay.mjs db "<sql>" [params…]`, `relay.mjs db --file <path>` (statements split on `;` at line ends, sent as one batch), and `relay.mjs db tables`.

## Risks / Trade-offs

- [Free commands fill a database or run long] → the limits in §2; Cloudflare's per-request CPU limit ends a long command.
- [An agent copies health or places into its tables] → the server never does; the skill says not to; only the person's own computers reach it.
- [A Worker deletes a space but has no `WORKBENCHES`] → the type makes it required wherever a space opens, so the build fails.

## Migration Plan

1. Publish the spaces Worker first, with tag `v2`, then the server and the connector, in [the Workers' order](../../../wiki/relay-spaces.md#the-workers-and-their-order).
2. Rollback: revert. An unused `Workbench` class costs nothing.

## Open Questions

None.
