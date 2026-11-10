# A database of their own for the agents on your computers

**Status:** ready-to-ship
**Branch:** relay-memory-plugin
**Open questions:** none

## Why

Agents want to keep their own data next to yours, and today they can't make a single table. Relay Everything's own tables must stay out of their reach, so each person gets a second database only for agents.

## What Changes

- **Agents get a database of their own.** Each person gets a second database, only for their agents. An agent on your computer can make any table there and send it any database command. Relay Everything's own tables (notes, health, places, chats, memory) are not in it, so no command can reach them. Deleting your account deletes it too.
  ```svg
  <svg viewBox="0 0 600 200" font-size="14">
    <rect x="10" y="10" width="280" height="180" rx="8" fill="card" stroke="fg"/>
    <text x="150" y="38" text-anchor="middle">Your space</text>
    <text x="150" y="66" text-anchor="middle" fill="muted">notes · health · places</text>
    <text x="150" y="88" text-anchor="middle" fill="muted">chats · memory</text>
    <text x="150" y="150" text-anchor="middle" fill="muted">only Relay Everything writes here</text>
    <rect x="310" y="10" width="280" height="180" rx="8" fill="card" stroke="line"/>
    <text x="450" y="38" text-anchor="middle">Agents' database</text>
    <text x="450" y="66" text-anchor="middle" fill="muted">any table, any command</text>
    <text x="450" y="150" text-anchor="middle" fill="muted">from your computers only</text>
  </svg>
  ```
  No real picture: this is a map of the parts, not a screen.

- **One command in the plugin.** The AI sends a command, or a file of commands, and lists the tables other agents made.
  ```text
  relay.mjs db "CREATE TABLE reading_list (title TEXT, done INTEGER)"
  relay.mjs db --file plan.sql
  relay.mjs db tables
    reading_list  title, done  3 rows
  ```

- **Limits keep it fair.** A command up to 100 KB, 50 commands in one step, an answer up to 5,000 rows and 5 MB, and a database up to 1 GB. A command past a limit is refused with the limit, and nothing it did stays.

**Not breaking:** nothing that works today changes.

## What the build needs

- **Every choice**: Ready. Asked in the chat.

## Capabilities

### New Capabilities

- `relay-agent-database`: a second database for each person, only for their computers' agents, with free tables and commands, and no way into the space.

### Modified Capabilities

- `relay-agent-plugin`: the plugin gives the AI the agents' database.
- `relay-knowledge-web`: plugins still make no table in the space, but they get their own database.
- `relay-person-spaces`: deleting an account deletes the agents' database too.

## Impact

- **Server:** `app/worker/spaces-worker.ts` gains a second Durable Object class, `Workbench`; `app/worker/apps/relay/space.ts` opens it and deletes it with the space; the connector's web API gains `POST /v1/db` and `GET /v1/db/tables`; `wrangler.spaces.jsonc`, the Workers that bind spaces, and the self-host templates bind the new class.
- **Plugin:** `plugin/bin/relay.mjs` gains `db`; the `ask` skill says when to use it.
- **Docs:** `wiki/relay-spaces.md`, a new site page `api/agents-database.md`, `npm run relay:api-doc`, `plugin/README.md`.

## Decision log

- **2026-11-10** — Asked how agents make and use their own tables → chose free database commands in a second database for each person, which holds only agent tables, so Relay Everything's tables are never in reach.
- **2026-11-10** — Asked, at `/ship`, whether to wait for WongStack's memory change → chose to ship the agents' database now as its own change; the memory part stays planned in `relay-memory-plugin`.
- **2026-11-10** — Assumed: the agents' database is a second Durable Object for each person, in the same spaces Worker but its own class, because a Durable Object has one SQLite database, and a separate one is the only way free commands can't reach the space's tables.
- **2026-11-10** — Assumed: only a computer key reaches the agents' database; API keys, the AI connector and phone keys are refused, because the plugin runs only on computers.
- **2026-11-10** — Assumed: deleting the space deletes its agents' database in the same step, so every place that deletes a space can't forget it.
- **2026-11-10** — Assumed: a blob reads back as `{ "base64": … }`, because JSON has no bytes, and a blob that read as `{}` would lose data without a word.
- **2026-11-10** — Archive checkpoint: merged `main` (#104, the daily knowledge build) into the branch; the plugin goes to `0.5.1` on top of its `0.5.0`, and the memory plan moved to its own branch, `relay-memory-plugin-plan`.
