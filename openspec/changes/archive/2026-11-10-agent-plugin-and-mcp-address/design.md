# Design

## Context

- The connector Worker `relay-everything-mcp` answers on `relay-everything-mcp.matthewwong525.workers.dev` (`app/wrangler.relay-mcp.jsonc`, `workers_dev: true`, `RELAY_MCP_ADDRESS`). The app's `RELAY_MCP_CALLBACK` (`app/wrangler.relay.jsonc`, staging in `app/wrangler.jsonc` too) names its `/callback`. `device.ts`'s `apiAddress` reads that callback's origin for the web API's `/v1`.
- The plugin (`plugin/`) has three hooks, a stdio MCP server `relay-save` (`save_to_relay`), the skills `saving` and `connect-ai`, and a required `userConfig.connect_code` that holds a chat key (`reaches = 'chats'`: `POST chats`, `POST chat-saves`, `GET key`).
- The web API (`/v1/` on the connector Worker) takes only `reaches = 'api'` keys (`apiKeyCaller` in `caller.ts`) and already reads notes, days, health, nights, workouts, places, calendar and chats, and adds notes.
- The phone's sign-in (`sign-in/phone.ts`) already does a code-and-secret trade for a key; the plugin's link sign-in reuses its shape, but the computer polls because a terminal has no address the browser can open.
- Tried on this computer, 2026-11-10: `claude plugin marketplace add matthewwong525/RelayEverything` plus `claude plugin install relay@relay`, and `codex plugin marketplace add …` plus `codex plugin add relay@relay`, both install. Codex reads Claude-format plugins: it used a plugin skill, and it parsed the plugin's `hooks/hooks.json`. A probe hook did not run in `codex exec`, so Codex may need the person to trust plugin hooks once.

## Goals / Non-Goals

**Goals:** the connector at mcp.relayeverything.com; one plugin for Claude Code and Codex that connects by link, saves chats from both, reads and adds through skills with no MCP server, and points out a doubled connector; *Other connections* on the phone; clear steps, tried end to end on staging from this computer.

**Non-Goals:** see the proposal's Non-goals.

## Decisions

### 1. The connector's address

- `app/wrangler.relay-mcp.jsonc`: `"routes": [{ "pattern": "mcp.relayeverything.com", "custom_domain": true }]`, and in `env.staging` `mcp-staging.relayeverything.com`. `RELAY_MCP_ADDRESS` becomes `https://mcp.relayeverything.com/` (staging: `https://mcp-staging.relayeverything.com/`): the provider's one resource is the bare origin. `workers_dev` becomes `false`: the old address can't keep its grants, so it stops rather than refusing each app.
- **MCP at `/`.** The provider's `apiRoute` stays `/mcp`, because `/` as a route prefix would take `/authorize` and `/callback` too. `index.ts`'s `fetch` sends an MCP request on exactly `/` (`POST`, `DELETE`, or a `GET` that accepts `text/event-stream`) to the provider as the same request on `/mcp`. A token bound to the bare origin passes the provider's audience check on `/mcp`, because a resource of `/` covers every path (`audienceMatches`). A plain browser `GET /` answers a short HTML page: *Relay Everything's AI connector. Add https://mcp.relayeverything.com to your AI app.* The `401` challenge and `/.well-known/oauth-protected-resource` name the bare origin, so a client that adds the bare address finds matching metadata.
- `tokenCaller` compares a token's audience with `RELAY_MCP_ADDRESS` through the provider's own match, not `===`, so `https://mcp.relayeverything.com` and `…/` are one resource. `challenge()` names `/.well-known/oauth-protected-resource` for a bare origin. `Grants.list` answers the address with no trailing slash, for people to copy.
- `RELAY_MCP_CALLBACK` in `app/wrangler.relay.jsonc` and in `app/wrangler.jsonc`'s staging block becomes `https://mcp.relayeverything.com/callback` (staging likewise). `apiAddress` then answers `https://mcp.relayeverything.com/v1`.
- Tests in `relay-mcp/`: an MCP `initialize` on `/` and on `/mcp` with one token; a browser `GET /` gets the page; the protected-resource metadata names the bare origin; a token made for the old resource is refused.
- `self-host/mcp.template.jsonc` and `self-host/` setup: a self-hosted connector's `RELAY_MCP_ADDRESS` becomes its bare origin too, so self-hosters also add the bare address; an update tells them to connect their apps again.
- `scripts/relay-mcp-trial.mjs` and `scripts/company-api.mjs` default to the new addresses; `scripts/relay-mcp-setup.mjs` makes nothing new (a custom domain comes with the Worker's deploy).
- Alternative: keep `/mcp` as the resource and only rewrite `/`. Rejected: a client that adds the bare address would get metadata naming another resource, which a strict client refuses.

### 2. A computer's key: reach `agent`

- New reach `agent`. Directory migration `schema/migrations/<ts>_relay_agent_keys.sql` rebuilds `relay_keys` with `reaches IN ('phone', 'chats', 'api', 'agent')`, keeping every row (the shape of `20261107210000_relay_api_keys.sql`). Space migration `schema/space-migrations/0015_agent_devices.sql` rebuilds `relay_devices` with `'agent'` added (the shape of `0009_inbox.sql`), and adds `relay_chats.app TEXT NOT NULL DEFAULT 'claude-code' CHECK (app IN ('claude-code', 'codex'))`.
- `caller.ts`: `REACH.agent` reaches `POST chats` and `POST chat-saves` and `GET key`, like `chats`. `apiKeyCaller` takes `api` or `agent`; its refusal for `chats` says to run `/relay:connect`. The web API's adder (`relay-mcp/asker.ts`) treats `agent` as it treats `api`: a note it adds is the computer's device's note.
- `device.ts`'s `reaches` enum lists `agent` for the list; `deviceAdd` refuses `agent` and `chats` (only the link makes a computer's key; no new chat key). `makeDevice` takes `agent`.
- Alternative: widen `chats`. Rejected: each chat key was made under the promise *it can only add chats*.

### 3. Link sign-in for a computer

Routes in `app/worker/apps/relay/sign-in/computer.ts`, listed in `sign-in/index.ts`, with a directory table `relay_computer_codes (challenge TEXT PRIMARY KEY, words TEXT, name TEXT, person_id TEXT, expires_at INTEGER)`:

| Route | Does |
| --- | --- |
| `POST sign-in/computer` `{ challenge, name }` | Rate-limited by IP (`limited`). Keeps a row for 10 minutes; answers `{ link, words }`: the link is `<origin>/apps/relay/sign-in/computer?c=<challenge>`, the words a short code such as `KITE-4821`. |
| `GET sign-in/computer?c=` | Signed out: the sign-in, then back. Signed in: *Connect this computer?* with its name (editable), the code, *Check that this code is the one on your computer. Connect only a computer you just started this on.*, and what the key can do: *It saves your AI chats and reads all your Relay Everything data. You can turn it off in Devices.* |
| `POST sign-in/computer` (form) | *Connect* sets `person_id`; *Cancel* deletes the row. |
| `POST sign-in/computer/key` `{ verifier }` | SHA-256 of the verifier finds the row. Not yet confirmed: `202 { "waiting": true }`. Confirmed: deletes the row, makes the `agent` device and answers `{ server, key, api, name }` once. Gone or too old: `400`. |

The secret (verifier) never leaves the computer until the trade, as in `phone.ts`; the link holds only its hash.

### 4. The plugin

```text
plugin/
  .claude-plugin/plugin.json   no userConfig
  hooks/hooks.json             SessionStart, Stop, SessionEnd
  bin/connect.mjs              start | wait | status | forget
  bin/relay.mjs                read and add, through /v1
  bin/save.mjs                 a chat's save with title + summary
  bin/saving.mjs, bin/hook.mjs
  lib/config.mjs               the key file and the state folder
  lib/transcript.mjs           Claude Code transcripts
  lib/codex.mjs                Codex rollouts
  skills/connect, ask, save, saving
```

- **No MCP server.** `.mcp.json`, `bin/save-server.mjs`, `bin/connect-ai.mjs`, `skills/connect-ai` and `userConfig` go. `version` becomes `0.3.0`.
- **One folder per computer.** `lib/config.mjs` keeps the key at `${XDG_CONFIG_HOME:-~/.config}/relay-everything/computer.json` (`{ relay: 1, server, key, api, name }`, file mode `0600`, folder `0700`), and the hooks' state beside it in `state/`. Claude Code and Codex share both, so *saving off* in a project holds for both. On first run it copies the off-projects from an old `CLAUDE_PLUGIN_DATA` state. `RELAY_EVERYTHING_HOME` points elsewhere for tests and the trial.
- **Connect.** `connect.mjs start [server]` (default `https://app.relayeverything.com`) makes a verifier, posts the challenge with the computer's host name, prints the link and the code, and starts a detached waiter that polls `sign-in/computer/key` every 3 seconds for 10 minutes and writes the key file. The skill shows the link and code, asks the person to say when they clicked *Connect*, then runs `connect.mjs wait`, which waits up to 90 seconds for the file. The Bash step never runs for 10 minutes, so neither app's command time limit stops it.
- **Doubled connector.** After the key is written, `connect.mjs` runs `claude mcp list` and `codex mcp list`, when each exists, with a 20-second timeout. It names each entry whose address is on the connector's host, or whose name is `relay` or *Relay Everything*, with its remove command (`claude mcp remove <name> -s <scope>`, `codex mcp remove <name>`). It prints, for a `claude.ai` entry: *turn it off in /mcp, or remove it in the Claude app's connector settings*. The skill tells the AI to ask before it runs a remove command.
- **Read and add.** `relay.mjs <command>` calls `<api>/<route>` with the key and prints the JSON answer: `me`, `notes [--q] [--from] [--to] [--cursor]`, `note <id>`, `day <YYYY-MM-DD>`, `health <type> [--from] [--to] [--per]`, `nights`, `workouts`, `places`, `calendar [--q]`, `chats [--q]`, `chat <id> [--cursor]`, and `add-note`, which reads the words from stdin. A `403` from a chat key prints *This computer's key only saves chats. Type /relay:connect to connect it again.* The `ask` skill lists the commands in a few lines, and names the time-zone rule, with no tool schemas.
- **Save.** `save.mjs` takes a title and a summary on stdin, finds this chat (Claude Code: `${CLAUDE_SESSION_ID}` in the skill; Codex: the newest session in the state for this folder, by the hooks' records), sends its new messages and then `POST chat-saves`, as `save_to_relay` did.
- **Hooks in both apps.** One `hooks.json`. The commands use `${CLAUDE_PLUGIN_ROOT}`; the build checks what Codex sets and, if it differs, falls back in the command (`${CLAUDE_PLUGIN_ROOT:-$PLUGIN_ROOT}`) with a test on the file. `SessionEnd`'s timeout drops to 3 seconds, which Codex already forces. `hook.mjs` tells the apps apart by the transcript's first line (Codex rollouts start with `session_meta`) and sends `app: 'codex'` or `'claude-code'`.
- **Codex rollouts.** `lib/codex.mjs` turns `response_item` lines into messages: a `message` from `user` that is not injected context (`<environment_context>`, `<user_instructions>`, `AGENTS.md` text) is `you`; one from `assistant` is `ai`; a `function_call` or `local_shell_call` is one step line (`Ran: npm test`); `reasoning` and every output are dropped. The same `hide.mjs` runs on each. A fixture rollout from this computer, with its text replaced, drives the test.
- **No address or key in the folder.** `test/no-secrets.test.mjs` allows `https://app.relayeverything.com` and still refuses key shapes, emails and `workers.dev`.

### 5. Chats name their app

`POST chats` takes an optional `app` (`claude-code` or `codex`, default `claude-code`), kept from the first send. The page's list and chat, `GET /v1/chats`, `GET /v1/chats/{id}`, and the connector's `search_chats` and `read_chat` answer `app`. `npm run relay:api-doc` updates the reference.

### 6. The phone and the web page

- `mobile/lib/screens/home.dart`: on the phone (no `otherConnections`), a second section *Other connections* after *On this phone*, with one `FolderRow` *AI chat transcripts* (`CupertinoIcons.chat_bubble_2`, line *Claude Code and Codex*), folding like the others. It opens `screens/transcripts.dart`.
- `transcripts.dart`: the steps in plain words (install in Claude Code or Codex, `/relay:connect`, click *Connect*), each command in a copyable box, and, when signed in to a Relay Everything server, *Read them on the web*, which opens `<server>/#chats`. No network call.
- Web: `shell.dart` names the row *AI chat transcripts* and opens `ChatsPlace` for `#chats`; `chats.dart` shows each chat's app as a small tag; `devices_page.dart` drops *Claude Code* from *Add a device*, and lists `agent` as *Claude Code or Codex* and `chats` as *Claude Code, saves only*, with a line *Connect a computer from Claude Code or Codex with /relay:connect*.

### 7. Docs

`plugin/README.md` and `site/src/content/docs/connections/claude-code.md` (title *Save AI chat transcripts*, same address) are rewritten as numbered steps: install in Claude Code, install in Codex (with the trust step if Codex needs one), connect, ask, save, turn saving off, what is sent, what stays on the computer. `connections/connect-your-ai.md` names `mcp.relayeverything.com/mcp` and sends Claude Code and Codex users to the plugin. `api/keys.md` describes a computer's key and marks the chat key as older. `wiki/stack/relay-ai-connector.md` and `wiki/stack/relay-chats.md` follow; `scripts/product-name.test.mjs` lists the new skill files.

## UX

**Use-case brief.** The person has Relay Everything on their phone and uses Claude Code or Codex on a computer. The job: find out, from the phone, that AI chats can be saved, and how. Done is: they know the two steps, and, if signed in, can open their chats on the web. Context: at a glance, on the phone, rarely (once per computer). The common case is signed in; the edge case is the offline default, signed out. Closest existing screen: the *Health* page under *On this phone*, a page that explains and links.

**Shortest flow.** Home → *AI chat transcripts* → read the steps → *Read them on the web* (signed in).

**Hierarchy.** One primary action: *Read them on the web* when signed in; none when signed out (the steps are the content).

**Components.** The existing `FolderRow`, `_FoldHeader` and `_Card` on Home; on the page, the large-title page shell the data pages use, text blocks, a copyable command box like the Account page's, and one filled button.

### Review

The review page (`review.html`) sketches Home in *The phone gets an Other connections section* and the web left bar in *Codex chats save too, as AI chat transcripts*.

## Risks / Trade-offs

- **A computer's key reads everything.** A lost laptop reads all data until its key is turned off. The link page says so, and Devices lists each computer.
- **Link phishing.** Someone could send a person a link they started. The page shows the code and warns; the link works 10 minutes, once.
- **Codex hook trust.** If Codex needs a one-time trust for plugin hooks, chats won't save until the person gives it. The docs and `/relay:connect` say the step; the trial checks it.
- **Claude Code's own session id in skills.** If `${CLAUDE_SESSION_ID}` isn't filled, `save.mjs` falls back to the newest session for the folder, as in Codex.
- **Old installs.** A computer with the 0.2 plugin keeps saving with its chat key through Claude Code's stored option until it updates. After the update the plugin no longer reads that option: `/relay:connect` once is needed, and the session-start hook says so once.
