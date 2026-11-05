# Design

## Context

Relay's server is the `relay` mini app on `main`, shipped by relay-app-first-version. Its routes sit in `app/worker/apps/relay/api.ts`; `device.ts` gates every Access service token: an unrevoked `relay_devices` row reaches only `DEVICE_ROUTES`, and `deviceOf` names the caller. `scripts/relay-device-key.mjs create` makes a service token, adds it to the `Relay devices` policy, records it, and prints `connectCode()` = `{"relay":1,"server","clientId","clientSecret"}` as a QR code and on a private hand-over page under `~/.relay-ring/device-keys`.

The read-only AI connector is [relay-ai-connector](../relay-ai-connector/design.md) (workspace "PLAN: Relay MCP server"): Worker `relay-ring-mcp` in `app/worker/relay-mcp/`, tools over read functions in `app/worker/apps/relay/queries.ts`, a test that fails on any statement but `SELECT` there.

Claude Code plugins ([plugins reference](https://code.claude.com/docs/en/plugins-reference), [hooks](https://code.claude.com/docs/en/hooks)), checked 2026-11-05 against Claude Code 2.1.310:

- A marketplace is `.claude-plugin/marketplace.json` (`name`, `owner`, `plugins[{ name, source: "./relay" }]`); a plugin has `.claude-plugin/plugin.json`, `hooks/hooks.json`, `.mcp.json`, `skills/<name>/SKILL.md`.
- `userConfig` in `plugin.json` is asked at enable time; `sensitive: true` goes to the system's secure store. Hooks get it as `CLAUDE_PLUGIN_OPTION_<KEY>`; a stdio MCP server only through `env` with `${user_config.KEY}`.
- `${CLAUDE_PLUGIN_DATA}` (`~/.claude/plugins/data/<id>/`) survives updates; `${CLAUDE_PLUGIN_ROOT}` does not.
- Hook input carries `session_id`, `transcript_path`, `cwd`. SessionEnd hooks share a 1.5 s budget by default; `"async": true` runs a command hook in the background. Stdio MCP servers get `CLAUDE_CODE_SESSION_ID`.

## Goals / Non-Goals

**Goals:** incremental, idempotent chat upload from hooks; a save tool; per-project off; key hiding before upload; chat-only device keys; Chats on the Relay page; two connector tools; a plugin that holds no key or address, installed from this repository.

**Non-Goals:** setting up a self-hosted server (workspace "Self-host Relay on your own server"), other chat apps, past transcripts, webhooks for chats, the phone app, encryption beyond TLS and Cloudflare's at-rest storage.

## Decisions

### Server: three tables, no R2

Migration `schema/migrations/<ts>_relay_chats.sql`, additive:

- `relay_devices` gains `reaches TEXT NOT NULL DEFAULT 'phone' CHECK (reaches IN ('phone', 'chats'))`. Existing rows stay phones.
- `relay_chats(id TEXT PK, device_id REFERENCES relay_devices, session_id TEXT, app TEXT CHECK (app = 'claude-code'), project TEXT, title TEXT, started_at, last_at, message_count INTEGER, created_at, UNIQUE (device_id, session_id))`, index on `last_at`.
- `relay_chat_messages(chat_id REFERENCES relay_chats ON DELETE CASCADE, seq INTEGER, role TEXT CHECK (role IN ('you', 'ai', 'step')), text TEXT, at INTEGER, PRIMARY KEY (chat_id, seq))`.
- `relay_chat_saves(id TEXT PK, chat_id REFERENCES relay_chats ON DELETE CASCADE, title TEXT, text TEXT, created_at)`.

Why D1 rows over an R2 body, as audio uses: search and parts need rows, and messages-only chats are small. One message is capped at 200,000 characters; the plugin cuts a longer one and ends it with `[cut: N more characters]`. Deletion deletes children explicitly in one batch as well, since D1 enforces foreign keys but a test should not rely on `ON DELETE` alone.

Routes in `app/worker/apps/relay/`, each its own file, by the shared contract:

- `POST chats` (`chats.ts`): `{ sessionId, project, startedAt, title?, messages: [{ seq, role, text, at }] }`, at most 500 messages and 4 MB. Upserts the chat on `(device, sessionId)` without changing a stored title, project or start, inserts messages `ON CONFLICT (chat_id, seq) DO NOTHING`, sets `message_count` to the stored count and `last_at`, answers only `{ stored }`. A gap (first `seq` > `stored`) is refused with 400 and the answer's `stored`, so the plugin resends from there.
- `POST chat-saves` (`chats.ts`): `{ sessionId, title, text }` on an existing chat; adds a save row and answers `{ ok: true }`. The read queries show the newest save's title as the chat's title, so a key never changes a stored row.
- `GET chats?q=&before=&limit=` (`chat-read.ts`): newest first, paged like `timeline`; `q` matches every word with `LIKE` over messages and saves, case-insensitive.
- `GET chat?id=&after=&limit=`: the chat, its saves, and up to 200 messages after `after`, with `next`.
- `DELETE chat?id=`.

The read queries live in `queries.ts` beside the connector's, `SELECT` only; delete lives in `chat-read.ts`.

`device.ts`: `DEVICE_ROUTES` becomes two lists by `reaches`: phones keep today's list; `chats` keys reach only `POST chats` and `POST chat-saves`. The gate checks the method too, because `GET chats` shares the path. `chats.ts` refuses any caller but a `chats` device on `POST`; the read and delete handlers refuse every device key through `deviceOf`, so a phone key can't read chats either.

The chat key is send-only, as the self-host shape asks: add, no list, read, change or delete. The `stored` count names only the chat that key sent, so the plugin resumes without reading.

`scripts/relay-device-key.mjs create --for claude-code` records `reaches = 'chats'`, names the token `relay-ring chats <name>`, and prints the connect code as text only (no QR: it is pasted on a computer). `list` shows each key's reach.

### Plugin: `plugin/` in this repository

```text
.claude-plugin/marketplace.json   name "relay", one plugin, source ./plugin
plugin/
  .claude-plugin/plugin.json      userConfig.connect_code: string, sensitive, required
  README.md                       install, connect code, what is sent, saving off
  hooks/hooks.json
  .mcp.json                       relay-save: node ${CLAUDE_PLUGIN_ROOT}/bin/save-server.mjs
  skills/saving/SKILL.md          /relay:saving [on|off]
  skills/connect-ai/SKILL.md      /relay:connect-ai <address>
  lib/                            transcript.mjs, hide.mjs, send.mjs, state.mjs, code.mjs
  bin/                            hook.mjs, save-server.mjs, saving.mjs, connect-ai.mjs
  test/                           node --test, fixtures of real transcript lines
```

Plain Node 20+, no npm packages, so install needs no build step and the plugin carries no lockfile to watch. Anyone adds it with `/plugin marketplace add matthewwong525/RelayEverything`, because the repository is public.

- **Hooks** (`bin/hook.mjs <event>`): `SessionStart` (startup, resume, clear, compact) records `session_id → transcript_path, cwd` in `${CLAUDE_PLUGIN_DATA}/sessions.json` and sends any session marked pending; `Stop` with `"async": true` records and sends; `SessionEnd` spawns a detached `hook.mjs send <session>` and returns at once, so the 1.5 s budget never cuts a send. Each send takes a lock file per session, so a Stop and an end don't send twice at once.
- **Reading a transcript** (`lib/transcript.mjs`): JSONL lines in order. A `user` line with string content or `text` blocks is `you`; `tool_result` blocks are dropped. An `assistant` line's `text` blocks are `ai`; `thinking` is dropped; each `tool_use` becomes one `step`: `Ran: <first line of command, 200 chars>`, `Read <path>`, `Edited <path>`, `Wrote <path>`, `Searched: <pattern>`, `Fetched <url host>`, `Asked a helper: <description>`, else `Used <tool name>`. Paths are made relative to `cwd`. Sidechain lines (`isSidechain`) and meta lines are skipped. Images become `[image]`. `seq` counts kept items from 0, so the same file always yields the same numbers. Title: the transcript's `custom-title` or `summary` line, else the first `you` line, 80 characters.
- **Hiding** (`lib/hide.mjs`): the token shapes of `.claude/skills/memory/scripts/lib/scan.mjs` (GitHub, `sk-`, AWS, JWT, Bearer, private key blocks, Slack), plus `.env` values of 8+ characters from `cwd`'s nearest `.env` and `.dev.vars`, replaced with `[hidden]`. Copied, not imported: Claude Code installs only the `plugin/` folder, so the plugin can't reach the rest of the repository. A test runs both on the same samples, so a new shape in one fails until the other has it.
- **Sending** (`lib/send.mjs`): parses the connect code from `CLAUDE_PLUGIN_OPTION_CONNECT_CODE`, posts to `<server>/apps/relay/api/chats` with `CF-Access-Client-Id` and `CF-Access-Client-Secret`, from the session's last `stored` in `sessions.json`, in batches under the caps; on a gap answer it resends from the given `stored`. Failure marks the session pending. Nothing is logged but the session id, counts and HTTP status, to `${CLAUDE_PLUGIN_DATA}/send.log`, last 200 lines.
- **Skipped**: a project in `${CLAUDE_PLUGIN_DATA}/off.json` (by its git top folder, else `cwd`), a chat with no `you` line, and any run with `RELAY_SAVE=0`.
- **Save tool** (`bin/save-server.mjs`): a minimal stdio MCP server (JSON-RPC `initialize`, `tools/list`, `tools/call`; written by hand, about 100 lines, to keep zero dependencies). One tool, `save_to_relay({ title, summary })`, `readOnlyHint: false`. It finds the transcript from `CLAUDE_CODE_SESSION_ID` in `sessions.json`; if that session was cleared, the newest session in the same project. It sends the chat, then `POST chat-saves`. The connect code reaches it through `.mcp.json` `env: { RELAY_CONNECT_CODE: "${user_config.connect_code}" }`.
- **Any Relay server**: `lib/code.mjs` takes the server address only from the connect code (`https://` and no path, as `relay-device-key.mjs` checks), and every request goes there; no address is built in. A self-hosted server that serves the same chat routes needs no plugin change. `README.md` and `ConnectClaude.tsx` carry one line suggesting a self-hosted server for chats kept in your own account; the link to its steps is added by the self-host change when those exist.
- **Skills**: `/relay:saving` runs `bin/saving.mjs [on|off]` and prints its one or two lines. `/relay:connect-ai` runs `bin/connect-ai.mjs <address>`, which checks the address is `https://…/mcp` and runs `claude mcp add --transport http --scope user relay <address>`.

### Public from the start

The repository is public, so the plugin gets no mirror and no publish script. [`scripts/public-check.mjs`](../../../scripts/public-check.mjs) checks `plugin/` on every change, like every other folder. A plugin test (`test/no-secrets.test.mjs`) also fails when any file in `plugin/` holds a `workers.dev` or other Relay address, or an email, which the public check does not cover.

### Connector tools

In `app/worker/relay-mcp/`, read-only like the rest:

| Tool | Input | Returns |
|---|---|---|
| `search_chats` | `query`, `from?`, `to?`, `limit≤20`, `cursor?` | chats matching every word: `id`, `title`, `project`, `startedAt`, `lastAt`, up to 3 matching lines (300 characters each) |
| `read_chat` | `id`, `cursor?` | the chat, its saves, and 200 messages per part, with `cursor` |

Both call `queries.ts`; the connector's `SELECT`-only test covers them. Neither returns `device_id` or `session_id`.

### Website

`site/src/content/docs/connections/claude-code.md`, *Save Claude Code chats*: install, the connect code, what is sent, saving off, delete, and running your own server. It writes `<your-relay-server>`, never the private site's address. The Connections index links it. `npm run relay:api-doc` in `app/` adds the chat routes to the API reference. Previews go through `node scripts/publish-relay-site.mjs --ref HEAD --staging`.

## UX

### Use-case brief
Matthew uses Claude Code many hours a day across several projects. He wants yesterday's decisions back without hunting through terminals. Done is a chat he can find on the Relay page by a word, or by asking his AI. Saving happens with no action; reading is a few times a week; connecting is once per computer. Edge cases: a private project (turn off), a secret pasted in chat (hidden), a chat saved by mistake (delete).

### Flow
Common case: nothing to do; chats appear on the Relay page. First time: Relay page → *Connect Claude Code* → run the key command → add the plugin in Claude Code → paste the code. Reading: Relay page → Chats → type a word → open a chat. Edge: `/relay:saving off` in the project; Delete in the chat view → confirm.

### Hierarchy
Chats card: the search box comes first; *Connect Claude Code* is a ghost button, since it's rare. Chat view: the messages are the content; *Delete* is a ghost danger button with a confirm. Saves sit above the messages, outlined, labeled *Written by the AI*. Steps are muted single lines, so the talk stands out.

### Review
[review.html](review.html) sketches the Chats card and the chat view (What Changes item 5) and the Connect Claude Code dialog (item 6). There is no prototype: the Relay page is not on `main` yet.

### Components
`Card`, `Input`, `Button`, `Badge`, `Dialog`, `AlertDialog` from `app/src/components/ui/`, like the rest of the Relay page. New: `Chats.tsx` (list and search), `Chat.tsx` (one chat), `ConnectClaude.tsx` (dialog), in `app/src/apps/relay/`.

## Risks / Trade-offs

- [The transcript format is Claude Code's, unpublished, and may change] → The reader keeps only lines it knows; unknown lines are skipped, never sent raw. Fixture tests use real lines. A step it can't name says `Used <tool>`.
- [Code and private talk leave the computer] → That is the feature, by Matthew's choice; tool output and files stay home, keys are hidden, a project can be turned off, and Delete removes a chat.
- [Hiding misses a secret that has no known shape] → Project `.env` values are also hidden; the README says what is and isn't caught.
- [The save tool finds the wrong session after `/clear`] → Hooks record each new session on `clear`; the tool picks the newest session in its project when its own id was cleared.
- [A detached send outlives Claude Code and fails] → It marks the session pending, and the next start sends it.
- [The connector change lands in another chat's code] → This build starts after the connector publishes and adds only two tools and queries; it does not change the connector's existing answers.
- [A core edit] → `device.ts` and `relay_devices` change; the change is additive and tested, and phone keys keep their routes.

## Migration Plan

The migration only adds a column and tables. Rollback: revert the Worker; the tables stay unused. Installed plugins keep sending until the chat key is revoked with `relay-device-key.mjs revoke`.
