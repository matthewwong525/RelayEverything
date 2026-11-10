# Design

## Context

The `ask` skill runs `plugin/bin/relay.mjs <command>`, which maps each command to one web API route with the computer's key (`COMMANDS` in `relay.mjs`). The web API already has `GET /v1/points` (by `id`, or `from`/`to`) and everything `around` needs: `/notes/{id}`, `/days/{day}`, `/notes?from&to`, `/places?from&to`, `/calendar?from&to`. Chat search needs `q`.

## Goals / Non-Goals

**Goals:** the topic list at chat start; a topic match on each message; a `topic` pull; a `points` command; an `around` command that joins several reads, health too; a skill that teaches thread-following from topics down.

**Non-Goals:** no server or API change; no writing of facts or pages (part 2); no photos (not in the web API); no chat search inside `around`; no change to chat saving.

## Decisions

- **Topics come from the copy.** `plugin/lib/topics.mjs` reads `copyOf(env)` (from `knowledge.mjs`): each `topics/*.md` and `topics/*/README.md` is a topic named by its path (`topics/ring/charging.md` → `ring/charging`), with its frontmatter `summary` and the `topics/…` paths it links. Top level is a name with no `/`. No copy, or no topics, gives an empty list. Reading is plain file reads, no git, so a hook stays well under its time limit.
- **Session start prints the list.** `hook.mjs session-start` keeps its recording and send, and also prints `Relay Everything topics:` with one line per top-level topic (`name  summary`, cut at 80 characters, at most 40 lines, newest `updated` first past that), plus the project's own topic when a topic has the project's name, and a last line naming `relay.mjs topic <name>`. It starts `knowledge.mjs sync` on its own, detached, like the send; the 15-minute rule in `sync` keeps it cheap. Not connected → the existing one notice only. Empty list → nothing.
- **Each message is matched.** A `UserPromptSubmit` hook, `hook.mjs prompt`, reads the prompt from stdin, lowercases it into words, and matches each topic: clear when the whole name (with `/` or `-` as spaces) or its last part is a word or words in the message; weak when a message word of 4 or more letters starts a topic's name part. It prints at most 3 lines, clear ones first with their summary, weak ones by name. No network call; under 200 ms on 1,000 topics. `RELAY_SAVE=0` does not stop it, because it only reads; a project with saving off still gets it, because saving off is about sending.
- **`topic <name>` pulls one step.** Reads the page from the copy and its linked topics both ways (links out from the page; links in by a scan of the copy's pages), then in parallel `GET /v1/memory?tag=<name>&limit=10`, `GET /v1/notes?tag=<name>&limit=5`, and, for the chat ids in those facts' `relay:chat/<id>` sources, up to 3 `GET /v1/chats/{id}` for title and summary only. One JSON answer `{ topic, summary, page, linked: {out, in}, facts, notes, chats, errors? }`; a failed part goes under `errors`. No page but facts with the tag → it still answers, with `page: null`.
- **`around` adds health.** One more parallel read, `GET /v1/health` for the window with `bucket=hour` for steps and heart rate, under `health`, so the AI sees the hours' health without a day's raw samples.
- **`points` is one more `COMMANDS` entry.** `points <id>` sets the `id` query field; `points --from … --to …` reads by time. Same shape as `health`, so no new code path.
- **`around` is a small composite in `relay.mjs`, not a server route.** `around <note id>` or `around --at <time>`, with `--hours <n>` (default 2, 1 to 12) and the usual `--timezone`. It reads the note first when given one, takes its `createdAt` as the moment, then reads the day, notes, places and calendar in parallel through the existing `api()` helper. It prints one JSON object: `{ at, from, to, timezone, note?, day, notes, places, calendar, errors? }`. A failed part goes under `errors` by name, so the rest still shows. A server route would serve the connector too, but it doubles the API surface for one client; the plugin can compose it.
- **Window arithmetic on wall-clock time.** A time with no offset is moved by hours as wall-clock text and sent with `timezone`, as every other read does. A time with an offset (a note's `createdAt`) is moved in UTC and sent with its offset. This keeps the server the one place that reads zones. Across a clock change the window may be an hour off at one edge; this is fine for context reads.
- **The day comes from the moment's local date** in the chosen zone (`Intl.DateTimeFormat` with `timeZone`).
- **Thread guide in the skill, as a short table.** Start → what to read next → when to stop. Kept in `SKILL.md`, under 40 more lines, because the skill's text loads only when it starts. The description gains trigger phrases (*what was I doing when*, *where was I*, *what did I decide about*, trips and stays).

- **A worktree resolves to its main repository.** `projectRoot` finds the nearest `.git`; when it is a file (`gitdir: …/.git/worktrees/<name>`), read the `commondir` beside that gitdir and take its parent as the root. No `git` call, so hooks stay fast. A broken or unreadable link falls back to the worktree path, as today. Saving's `off.json` keeps paths; an old entry for a worktree still matches its own path, so nothing breaks.

## Risks / Trade-offs

- [`around` makes 4 to 5 calls] → They run in parallel; each is bounded by the API's own limits.
- [The AI follows threads too far] → The skill says to stop when the question is answered, and to read at most one more step without a reason.

## Migration Plan

Plugin version 0.4.0. People get it with `/plugin update` or Codex's marketplace upgrade. Nothing to move or undo.
