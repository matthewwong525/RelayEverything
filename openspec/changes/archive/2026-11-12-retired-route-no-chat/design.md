# Design

## Context

`makeWorker().failed(kind, { note, reason })` in `.agents/skills/daily/scripts/worker.mjs` counts failures per kind in `needs-you.json`; the first writes `note()`'s journal line, the second opens `Needs you: <what>` through Paseo. `reason` is the server error as `<status>: <code>`, for example `404: retired`. The app answers each retired route with `fail("retired", 404)` (`app/worker/apps/inbox/retired.ts`), whose comment already promises that an older computer "logs one line and goes on". On 2026-11-12 the old worker had a `chats` kind; the server retired `POST chats-sync` before `/root/relay-ring` updated, so it opened the chat. The current code has no `chats` kind, but a future retired route could still reach the `morning` kind (a morning add-on that calls the server).

## Goals / Non-Goals

**Goals:** a `retired` answer never counts toward a Needs-you chat, for any kind.

**Non-Goals:** changing the order the server and computers update in; clearing the stale `chats` count left in `needs-you.json` (no code reads it).

## Decisions

- **Match in `failed`, not in each caller.** One check covers `paseo`, `morning` and any later kind. Test: `/^\d{3}: retired\b/` on `reason`.
- **One journal line, not silence.** Call `note()` once per day per kind with the reason, then return without changing `counts`, so the person can still find it.
- **Rejected: delay the server's retirement until all computers update.** The app can not know when every computer has updated; the client fix covers every case.
- **Upstream.** `worker.mjs` here is byte-identical to WongStack's `a282a4a9`. Build in WongStack first by its release rule (test, spec delta, changelog), then copy the same edit here so a later `/wong-sync` sees no difference.

## Risks / Trade-offs

- A real 404 named `retired` on a route that should work would hide behind one line → the journal still says it each day.

## Decision log

- **2026-11-12** — Asked whether the fix also goes to WongStack → chose yes, once it works here.
- **2026-11-12** — Assumed: a retired answer writes one journal line and counts nothing, because the app's `retired.ts` already promises that.
- **2026-11-12** — Assumed: build in WongStack first, then copy here, because the daily helper is WongStack's and a sync would undo a local-only edit.
- **2026-11-12** — Archive checkpoint: archived for /ship; the same fix is WongStack pull request #588 (release 56.0.1).
