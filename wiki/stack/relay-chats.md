# Relay Everything's Claude Code chats

Relay Everything saves Claude Code chats through the Relay Everything plugin in [`plugin/`](../../plugin/README.md): each chat goes to the Relay Everything server as you talk, shows in the **Chats** card on the Relay Everything page, and the [AI connector](relay-ai-connector.md) searches it. It is part of [the Cloudflare stack](README.md). The website's [Save Claude Code chats](../../site/src/content/docs/connections/claude-code.md) page owns the person's steps; this page owns how it works and how to change it.

## How a chat travels

1. A chat key, made with `node scripts/relay-device-key.mjs create --name "<computer>" --for claude-code`, is a device row with `reaches = 'chats'`. It reaches only `POST chats` and `POST chat-saves`; [`device.ts`](../../app/worker/apps/relay/device.ts) checks the method and path. A phone key (`reaches = 'phone'`) can't reach a chat route.
2. The plugin's hooks run `bin/hook.mjs`: `SessionStart` notes the session and sends any send that failed before, `Stop` sends the new messages, and `SessionEnd` starts a detached send so Claude Code's short end budget never cuts it.
3. [`lib/transcript.mjs`](../../plugin/lib/transcript.mjs) reads the transcript JSONL: what you typed, the AI's text, and one line per tool step. Tool output, thinking, helper chats and unknown lines are never sent. [`lib/hide.mjs`](../../plugin/lib/hide.mjs) replaces key shapes and `.env` values with `[hidden]` first.
4. [`chats.ts`](../../app/worker/apps/relay/chats.ts) stores messages once each by `(chat, seq)` and answers only `stored`. A gap answers 400 with `stored`, and the plugin sends again from there, as after a delete.
5. A person reads and deletes through [`chat-read.ts`](../../app/worker/apps/relay/chat-read.ts); every device key is refused there. The connector's `search_chats` and `read_chat` read through [`queries.ts`](../../app/worker/apps/relay/queries.ts).

`POST chats` is a bare route, not a contract action: the contract turns a 413 into a 400 and drops `stored` from an error. Its fields are on the website page, through `HAND_PAGES` in [`api-doc.ts`](../../app/worker/apps/relay/api-doc.ts).

## Change the plugin

- **No packages.** The plugin is plain Node 20 or later, with no `npm install`: Claude Code copies only `plugin/` to a computer, so it can't import anything else in the repository.
- **The key shapes are copied.** `lib/hide.mjs` copies the shapes of the memory store's [`scan.mjs`](../../.agents/skills/memory/scripts/lib/scan.mjs) by name. `plugin/test/hide.test.mjs` fails when `scan.mjs` gains a shape the plugin lacks.
- **No address or key in `plugin/`.** The server comes only from the connect code. `plugin/test/no-secrets.test.mjs` fails on a key shape, a `workers.dev` address or an email in the folder.
- **Test it:** `node --test plugin/test/*.test.mjs`, which `npm test` in `app/` also runs, and `claude plugin validate plugin`.
- **Ship a new version:** raise `version` in `plugin/.claude-plugin/plugin.json`. Claude Code updates an installed plugin only when the version changes.

## Try it on a preview

1. Make a staging chat key: `node scripts/relay-device-key.mjs create --name "Build check" --for claude-code --staging`.
2. In a new Claude Code session, run `/plugin marketplace add <this checkout's path>` and `/plugin install relay@relay`, then paste the code.
3. Have a short chat, then ask the AI to save it to Relay Everything. Open the preview's **Chats** card to see it.
4. Delete the chat, then run `node scripts/relay-device-key.mjs revoke --name "Build check" --staging`.

The connect code from step 1 names the staging server, but the chat routes of a new change live only on its preview. To send there, change the code's `server` to the preview's address before you paste it.

A plugin loaded with `claude --plugin-dir plugin` asks for no connect code. The hooks still run, but Claude Code skips the save tool's server with `Plugin option "connect_code" isn't set`. To try the save tool that way, use a copy of `plugin/` with no `env` in `.mcp.json` and no `userConfig`, and set `RELAY_CONNECT_CODE` before you start Claude Code. The plugin's own way, `/plugin install`, asks for the code.
