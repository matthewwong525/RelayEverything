# Tasks

## 1. Before the build

- [x] 1.1 Confirm `relay-ai-connector` is on `main` (`openspec list --specs` shows it beside `relay-notes`); if not, stop and say the build waits for it
- [x] 1.2 Read `app/worker/apps/relay/device.ts`, `queries.ts`, `scripts/relay-device-key.mjs` and `app/worker/relay-mcp/` as merged, and fit the design's names to them; record any change of shape in the Decision log

## 2. Server: chats in Relay

- [x] 2.1 Add the migration (`reaches` on `relay_devices`, `relay_chats`, `relay_chat_messages`, `relay_chat_saves`) and made-up seed rows in `schema/seed.sql`; verify with the D1 migration test in `npm test`
- [x] 2.2 Split `DEVICE_ROUTES` by `reaches` in `device.ts`, checking the method, with tests: a chat key reaches only `POST chats` and `POST chat-saves` and is refused on `GET chats`, `GET chat` and `DELETE chat`; a phone key keeps today's routes and is refused on every chat route
- [x] 2.3 Write `POST chats` and `POST chat-saves` with tests: upsert by session, the answer holds only `stored`, a repeat stores nothing new and changes no title, project or message, a gap answers 400 with `stored`, caps answer 413 and store nothing, a phone key is refused, a save adds a row and the list shows its title
- [x] 2.4 Write the read queries in `queries.ts` and `GET chats`, `GET chat`, `DELETE chat`, with tests: newest first and paged, every-word search over messages and saves, parts with `next`, delete removes messages and saves, every device key is refused
- [x] 2.5 Add `--for claude-code` to `scripts/relay-device-key.mjs` (reach `chats`, token name, text-only code) and the reach column to `list`, with tests in `relay-device-key.test.mjs`

## 3. Relay page

- [x] 3.1 Build `Chats.tsx`, `Chat.tsx` and `ConnectClaude.tsx` in `app/src/apps/relay/` as sketched (list, search, chat view with saves and muted steps, Delete with a confirm that says it can't be undone, the connect dialog with its self-host line), with tests in `App.test.tsx` for search, opening a chat, and delete

## 4. Connector tools

- [x] 4.1 Add `search_chats` and `read_chat` to `app/worker/relay-mcp/` on the `queries.ts` reads, read-only annotated, with tests: matching lines, parts with a cursor, no `device_id` or `session_id`; the `SELECT`-only test still passes

## 5. The plugin

- [x] 5.1 Make `plugin/` and the root `.claude-plugin/marketplace.json`, with `plugin.json` (`connect_code` sensitive), `hooks/hooks.json`, `.mcp.json`, `README.md` (with the self-host line); verify `claude plugin validate .` passes, and write `test/no-secrets.test.mjs` (no key shape, Relay address or email in `plugin/`)
- [x] 5.2 Write `lib/transcript.mjs` with fixture tests from real transcript lines: you and AI text exact, each tool step one line with a relative path, tool output, thinking and sidechains dropped, stable `seq`, the title rule, long messages cut with the marker
- [x] 5.3 Write `lib/hide.mjs` with tests: every token shape and `.env` value hidden, and a test that runs the memory store's `redact` on the same samples so the two lists stay equal
- [x] 5.4 Write `lib/state.mjs`, `lib/send.mjs` and `bin/hook.mjs` with tests against a fake server: only new messages sent, batches under the caps, a gap resends from `stored`, a failure marks pending and the next start sends it, the lock stops two sends at once, off projects, `RELAY_SAVE=0` and chats with no typed message send nothing, the log holds no text or key
- [x] 5.5 Write `bin/save-server.mjs` with tests over stdio: `tools/list` shows `save_to_relay`, a call sends the chat then the save, a cleared session falls back to the newest in its project, an off project is refused with how to turn it on
- [x] 5.6 Write `lib/code.mjs` with tests: the server comes only from the connect code, a code with a non-`https` or pathed address is refused, two codes for two servers send to their own server only
- [x] 5.7 Write the `saving` and `connect-ai` skills and their scripts, with tests: on, off and status lines; a bad address refused; `claude mcp add` called with the right arguments

## 6. Docs

- [x] 6.1 Add a *Save Claude Code chats* section to the relay wiki page (install, connect code, what is sent, saving off, delete, running your own server), linked from its hub; the repository's wiki checks pass

- [x] 6.2 Add `site/src/content/docs/connections/claude-code.md` and link it from the Connections index, run `npm run relay:api-doc` in `app/`, and preview with `node scripts/publish-relay-site.mjs --ref HEAD --staging`; its guard prints `result=clean`
- [x] 6.3 Add `site/src/content/docs/connections/connect-your-ai.md` (the Claude app, ChatGPT and Claude Code steps, what the AI can read, what leaves Relay, disconnect), replace the Connections index's MCP *Coming* note with a link to it, and use `<your-relay-server>` for every address

## 7. Check it works

- [x] 7.1 Run `npm test` in `app/`, `node --test plugin/test`, `node --test scripts/*.test.mjs` and `node scripts/public-check.mjs`; all pass and the check prints `result=clean`
- [x] 7.2 `/save`, then on the preview: make a staging chat key with `relay-device-key.mjs create --name "Build check" --for claude-code --staging`, add this checkout as a marketplace and install the plugin in a fresh Claude Code session, enter the code, have a short chat that runs one command and holds a fake key, and ask it to save to Relay; check the preview's Chats list shows the chat with exact messages, one step line, the key hidden and the AI's summary; check the chat key is refused on the timeline and on `GET chats`; delete the chat; revoke the key
