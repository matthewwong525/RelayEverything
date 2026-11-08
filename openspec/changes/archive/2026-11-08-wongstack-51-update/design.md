# Design: Update WongStack to 51.0.0

## Context

See proposal.md, Why. Source: `/root/.cache/wong-stack/WongStack` at `57208cc11cf518670ca7dcfeeba6c73ffd9d2c3a` (VERSION 51.0.0), refreshed on 2026-11-08 01:36 UTC (already up to date). Installed: 50.12.0 at `2acdf24b018a3596186316cc29a91ccfb40384b7`. The preflight (schema 1, `status: update`, categories core, ui, pack and scaffold, `catchUp.needed: false`, no diagnostics, 819 ms) found 86 changed units of 699. Its full report is `/tmp/preflight-51.json`; rerun the preflight if that file is gone.

`CLAUDE.md` already links to `AGENTS.md`, and `.claude` links to `.agents`. Logical `.claude/…` paths below are real files under `.agents/…`.

## Goals / Non-Goals

- Goal: every changed unit takes the 51.0.0 version, or a merge of it with this repo's own lines; every removed unit is deleted.
- Goal: the 51.0.0 *Updating* note is carried out: board read before publish, table and `checkerOwns` checks, daily settings check.
- Non-goal: any Relay Everything behavior change, any website page, any `relay_*` table.

## Decisions

### Unit routes, by preflight class

| Class | Count | Route |
|---|---|---|
| modified / installed-equivalent | 39 | Copy the source file over the target file. |
| added / missing | 9 | Copy. |
| removed / installed-equivalent | 33 | Delete. The target blob equals the 50.12.0 blob, so no local line is lost. |
| modified / locally-adapted | 5 | Apply the upstream hunk from 50.12.0 to 51.0.0 by hand; keep this repo's lines. |

Added (9): `.claude/skills/daily/scripts/chats.mjs`, `app/src/apps/inbox/{Archive.tsx,Archive.test.tsx,Chats.tsx,Chats.test.tsx,SearchField.tsx}`, `app/worker/apps/inbox/{chats.ts,chats.test.ts}`, `schema/migrations/20261107120000_inbox_chats.sql`.

Removed (33): `.claude/skills/daily/scripts/board.mjs`, `app/src/apps/inbox/{Reviews.tsx,Reviews.test.tsx}`, all of `app/src/apps/inbox/week/` (18 files), `app/src/lib/board.ts`, `app/tests/board.ts`, all of `app/worker/apps/inbox/tasks/` (10 files). Remove the empty `week/` and `tasks/` folders.

The full modified list is the preflight report's `changes`.

### The five locally-adapted units

- **`app/tests/employee-access/connections.ts`**: add `"20261107120000_inbox_chats.sql"` at the end of the core migration list (line 21), as upstream; keep this repo's second loop over the `relay_*` migrations.
- **`app/worker/api/contract.ts`**: drop `checkerOwns` from the re-export on line 12, as upstream; keep this repo's line 141 (`typeof route === "function"` guard).
- **`schema/seed.sql`**: append upstream's *Fay's open chats* block (the `chats` rows and the `inbox_items.chat` update) after the core seed rows; keep this repo's `relay_people` checker row.
- **`wiki/development/daily.md`**: take every upstream hunk (the chat list, *Reminders* in place of *The week board*, the `sources` line, the handoff). Keep this repo's link line to [`ship-every-chat.md`](../../../wiki/development/ship-every-chat.md); place it where its old neighbour text now sits. Check the page stays under 3,000 words.
- **`wiki/stack/mini-apps.md`**: take upstream's line 77 (the Inbox shows open chats and past review pages); keep this repo's queue-and-timed-job bullet.

### The database step

The new migration's name shares the `20261107120000` stamp with this repo's `20261107120000_relay_people.sql`. D1 tracks each migration by its full file name and sorts by name, so `inbox_chats` runs before `relay_people` on a fresh database and runs once, as unapplied, on staging and production. Neither file touches the other's tables, so the order is safe. No rename: a renamed upstream file would show as locally adapted in every later sync.

The drop lines stay. A search of `app/`, `schema/` and `scripts/` finds `tasks`, `week_goals` and `backlog_groups` only in WongStack's own `20261028120000_task_board.sql` and the removed board code. The new `chats` table has no clash: this repo's chat tables were `relay_chats` and its children, already dropped by `20261107180000_relay_drop_old_tables.sql`.

### The *Updating* note

- **Board tasks.** On 2026-11-08 `company-api.mjs call inbox.daily-tasks` for the weeks of 2026-10-19, 2026-10-26 and 2026-11-02 returned no tasks and only the empty `Other` backlog group. The build reads the current week and the four before it again, after the gate and before the publish. Any undone task found is listed for Matthew with one question, and each one he names becomes a one-time schedule through `/schedule`.
- **Daily settings.** There is no `.agents/daily/` folder, so no `tasks` entry to remove.
- **`checkerOwns`.** Only `app/worker/employee-access/{core,router,apps}.ts` use it, from `policy.ts`. No mini app imports it from `contract.ts`.

### No website page, no spec

The site describes Relay Everything's app, server, ring and connections; the Inbox is WongStack's owner tool. `skip_specs: true`: no capability in `openspec/specs/` changes.

## Risks / Trade-offs

- [Board data is gone for good] → read the board right before publish; it was empty at plan time.
- [`daily.md` merge drifts from upstream] → `merge-check.mjs` names any missing hunk before the install record changes.
- [A Relay Everything screen links to the old board] → none found: no file outside the inbox app imports `lib/board`, `tests/board` or the `tasks/` routes.
