# Relay Everything's AI chat transcripts

Relay Everything saves Claude Code and Codex chats through the Relay Everything plugin in [`plugin/`](../../plugin/README.md): each chat goes to the Relay Everything server as you talk, shows under **Connect your AI**, **Saved chats**, on the Relay Everything page, and the [AI connector](relay-ai-connector.md) searches it. The same plugin lets the AI in the chat read the person's data and add notes, through the web API. It is part of [the Cloudflare stack](README.md). The website's [Save AI chat transcripts](../../site/src/content/docs/connections/claude-code.md) page owns the person's steps; this page owns how it works and how to change it.

## How a computer connects

1. `/relay:connect` runs `bin/connect.mjs start`: it makes a secret, sends its SHA-256 and the computer's name to `POST sign-in/computer/start`, and shows the link and a code such as `KITE-4821`. A detached waiter asks `POST sign-in/computer/key` every 3 seconds for 10 minutes.
2. The person opens the link, signs in, checks the code and clicks **Connect** ([`sign-in/computer.ts`](../../app/worker/apps/relay/sign-in/computer.ts)). The row in `relay_computer_codes` then names them.
3. The next ask, with the secret, gets the key once: a device row with `reaches = 'agent'`, made by `makeDevice`. The plugin keeps it in its own key file, mode `0600`, under `RELAY_EVERYTHING_HOME` when set.

The start and the ask need no person: the secret protects them, so they pass a self-hosted server's Access wall (`NO_PERSON` in [`relay-only.ts`](../../app/worker/relay-only.ts)) and the Origin check. The ask has no rate limit: the secret is 256 bits and lives 10 minutes, and a limit of 10 a minute would refuse the waiter. **Add an API key** makes only an `api` key: never an `agent`, `chats` or phone key.

## How a chat travels

1. The computer's key goes as `Authorization: Bearer`. On the server it reaches only `POST chats`, `POST chat-saves` and `GET key`; [`caller.ts`](../../app/worker/apps/relay/caller.ts) checks the method and path. It reads through the connector's `/v1/`, as an API key does. An older chat key (`reaches = 'chats'`, from plugin 0.2) still sends, and `/v1/` refuses it with a line that says to run `/relay:connect`. A phone key can't reach a chat route.
2. The plugin's hooks run `bin/hook.mjs` in both apps: `SessionStart` notes the session and sends any send that failed before, `Stop` sends the new messages, and `SessionEnd` starts a detached send so the app's short end budget never cuts it. A session's project is its git top folder, and a worktree counts as its main repository (read from the `.git` file's `gitdir` and `commondir`, with no `git` call), so saving off and the project's name hold in each workspace copy.
3. [`lib/transcript.mjs`](../../plugin/lib/transcript.mjs) reads a Claude Code transcript and [`lib/codex.mjs`](../../plugin/lib/codex.mjs) a Codex rollout: what you typed, the AI's text, and one line per tool step. Tool output, thinking, helper chats and unknown lines are never sent. [`lib/hide.mjs`](../../plugin/lib/hide.mjs) replaces key shapes and `.env` values with `[hidden]` first.
4. [`chats.ts`](../../app/worker/apps/relay/chats.ts) stores messages once each by `(chat, seq)` and answers only `stored`. A gap answers 400 with `stored`, and the plugin sends again from there, as after a delete. `app` is `claude-code` or `codex`; the first send keeps it, and none means `claude-code`.
5. A person reads and deletes through [`chat-read.ts`](../../app/worker/apps/relay/chat-read.ts); every device key is refused there. The connector's `search_chats` and `read_chat` and `/v1/chats` read through [`queries.ts`](../../app/worker/apps/relay/queries.ts), each with the chat's `app`.

`POST chats` is a bare route, not a contract action: the contract turns a 413 into a 400 and drops `stored` from an error. Its fields are on the website page, through `HAND_PAGES` in [`api-doc.ts`](../../app/worker/apps/relay/api-doc.ts).

## How the AI reads

The `ask` skill runs `bin/relay.mjs`, which maps each command to one `/v1/` route with the computer's key. Two commands join reads into one answer, and a part that fails goes under `errors` by name: `around` reads a note, then its day, notes, places, calendar and hourly steps and heart rate in a window of 2 to 12 hours each way; `topic` reads a page and its links from the copy of the knowledge web, then the topic's facts, notes and up to 3 chats its facts name. A refused key stops the whole answer.

[`lib/topics.mjs`](../../plugin/lib/topics.mjs) reads the copy as plain files. At `SessionStart` the hook prints the top-level topics, at most 40, and starts `knowledge.mjs sync` detached; at `UserPromptSubmit` it adds at most 3 topics the message names. Both only read the copy, so they run with saving off or `RELAY_SAVE=0`, but not on a computer that is not connected. The first `SessionStart` of the day also starts the daily build: [how the web is built](relay-knowledge-web.md#how-the-web-is-built).

## Change the plugin

- **No packages.** The plugin is plain Node 20 or later, with no `npm install`: each app copies only `plugin/` to a computer, so it can't import anything else in the repository.
- **One plugin, two apps.** Claude Code and Codex both read `.claude-plugin/plugin.json`, `hooks/hooks.json` and `skills/`. Codex skips an `"async": true` hook and keeps `SessionEnd` to 3 seconds, so no hook is async: each ends at once and the send runs detached.
- **Codex runs only trusted hooks.** At its next start, Codex asks the person to trust the plugin's hooks (**Trust all and continue**, or `/hooks`), and again after an update that changes a hook. With no trust it runs none and says nothing, so no chat saves. `codex exec` runs an untrusted hook only with `--dangerously-bypass-hook-trust`.
- **What Codex gives a hook and a skill.** A hook gets `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA`, `PLUGIN_ROOT`, `PLUGIN_DATA` and `CODEX_HOME`, and on stdin `session_id`, `transcript_path` (the rollout under `~/.codex/sessions/`) and `cwd`. A skill gets no `CLAUDE_PLUGIN_ROOT` and no `$ARGUMENTS`, so each skill names its folder as two levels above `SKILL.md`; the session id is `CODEX_THREAD_ID`. Codex types a skill as `$relay:connect`, not `/relay:connect`.
- **The key shapes are copied.** `lib/hide.mjs` copies the shapes of the memory store's [`scan.mjs`](../../.agents/skills/memory/scripts/lib/scan.mjs) by name. `plugin/test/hide.test.mjs` fails when `scan.mjs` gains a shape the plugin lacks.
- **No key in `plugin/`, and one address.** The only address is the default server, `https://app.relayeverything.com`; the key file names the server after `/relay:connect`. `plugin/test/no-secrets.test.mjs` fails on a key shape, any other address or an email in the folder.
- **Test it:** `node --test plugin/test/*.test.mjs`, which `npm test` in `app/` also runs, and `claude plugin validate plugin`.
- **Ship a new version:** raise `version` in `plugin/.claude-plugin/plugin.json`. Each app updates an installed plugin only when the version changes.

## Try it on staging

Never install the plugin in your own setup to try it. Give each app a scratch home, so nothing touches `~/.claude` or `~/.codex`:

1. Make `.scratch/claude`, `.scratch/codex` and `.scratch/relay`. Copy `~/.claude/.credentials.json` into `.scratch/claude` and `~/.codex/auth.json` into `.scratch/codex`, so each app can sign in. Delete the folders when you finish.
2. Start each app with `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `RELAY_EVERYTHING_HOME` on those folders. Install from this branch: `claude plugin marketplace add <this checkout's path>` and `claude plugin install relay@relay`, or `codex plugin marketplace add <path>` and `codex plugin add relay@relay`.
3. In Codex, pick **Trust all and continue** for the hooks. Type `/relay:connect https://app-staging.relayeverything.com` (`$relay:connect …` in Codex), open the link signed in to staging, and click **Connect**. With no browser, add a test person and a session to the staging database, as [person spaces](../relay-spaces.md) says, and send the form with `curl`: `c`, `name`, `choice=connect`, the `__Host-relay_session` cookie and `Origin: https://app-staging.relayeverything.com`.
4. Have a short chat, ask *save this*, and ask about a seeded note. Open **Connect your AI**, then **Saved chats**, on staging to see the chat with its app.
5. Delete the chat, then click **Turn off** beside the computer in **Devices**. For a test person, `POST account-delete` with its email deletes the person, the chats and the key.

Run `codex exec` with stdin closed (`</dev/null`) and a time limit: it can wait for input forever. `codex exec` can't ask you to approve a command outside the sandbox, so it can't try the plugin as a person uses it. Start the Codex screen in `tmux new-session -d`, type with `tmux send-keys`, read it with `tmux capture-pane -p`, and press `y` at each *Would you like to run the following command?*.
