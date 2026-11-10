# Tasks

## 1. The connector's address

- [x] 1.1 `app/wrangler.relay-mcp.jsonc`: custom domains `mcp.relayeverything.com` and, in staging, `mcp-staging.relayeverything.com`; `RELAY_MCP_ADDRESS` on their bare origins; `workers_dev` off. `self-host/` names a bare origin too.
- [x] 1.2 `relay-mcp/index.ts`: MCP on `/` as on `/mcp`, a browser page on `GET /`, the audience match and the challenge for a bare origin. `RELAY_MCP_CALLBACK` on the new origins in `app/wrangler.relay.jsonc` and `app/wrangler.jsonc`. Tests per design 1.
- [x] 1.3 `scripts/relay-mcp-trial.mjs`, `scripts/company-api.mjs` and their tests default to the new addresses.

## 2. The server: a computer's key, link sign-in, chats' app

- [x] 2.1 Directory migration: `relay_keys.reaches` takes `agent`; table `relay_computer_codes`. Space migration `0015`: `relay_devices.reaches` takes `agent`; `relay_chats.app`.
- [x] 2.2 `caller.ts`, `space.ts`, `device.ts`: reach `agent` (chat routes, `GET key`, web API); `apiKeyCaller` takes it; `deviceAdd` refuses `agent` and `chats`. Tests: a computer key reads `/v1/notes` and sends a chat; it can't reach the page's routes, a phone's routes, the connector's tools, or delete; an old chat key still sends and is refused by `/v1`.
- [x] 2.3 `sign-in/computer.ts` and its routes: start, the confirm page, *Connect* and *Cancel*, the key trade. Tests: the whole trade; waiting before *Connect*; a second trade, a wrong secret and an old row make no key; signed out goes to the sign-in and back; the start is rate-limited.
- [x] 2.4 Chats' `app`: `POST chats` takes it and keeps the first; the page's chat list, `/v1/chats`, `/v1/chats/{id}`, `search_chats` and `read_chat` answer it; tests. `npm run relay:api-doc` in `app/`.
- [x] 2.5 `schema/seed.sql`: a computer device named `Laptop` and a Codex chat.

## 3. The plugin

- [x] 3.1 Remove `.mcp.json`, `bin/save-server.mjs`, `bin/connect-ai.mjs`, `skills/connect-ai`, `userConfig` and their tests; `version` `0.3.0`.
- [x] 3.2 `lib/config.mjs`: the key file and state folder, modes `0600` and `0700`, the copy of old off-projects, `RELAY_EVERYTHING_HOME`; tests.
- [x] 3.3 `bin/connect.mjs` (`start`, `wait`, `status`, `forget`) with the detached waiter and the doubled-connector check; `skills/connect`. Tests against a fake server and fake `claude`/`codex` commands: connect, time out, a found connector named with its remove command, a `claude.ai` entry named with the off step, nothing removed.
- [x] 3.4 `bin/relay.mjs` and `skills/ask`: each command's route and query; the chat-key refusal line; `add-note` from stdin. Tests against a fake server.
- [x] 3.5 `bin/save.mjs` and `skills/save`; `skills/saving` on the shared state. Tests: a save in Claude Code by session id, in Codex by the newest session for the folder, nothing with saving off.
- [x] 3.6 `lib/codex.mjs` and `hook.mjs`'s app check, with a redacted Codex rollout fixture; hooks' commands and timeouts for both apps; tests for the parse, the hidden keys and the `app` sent.
- [x] 3.7 `test/no-secrets.test.mjs` allows `https://app.relayeverything.com` only; `claude plugin validate plugin` and `claude plugin validate .` pass.

## 4. The phone and web app

- [x] 4.1 `screens/home.dart`: *Other connections* with *AI chat transcripts* on the phone, folding; `screens/transcripts.dart`. Widget tests: Home's three sections, the page signed out (no link, no request) and signed in (the link opens `<server>/#chats`).
- [x] 4.2 Web: `shell.dart` row *AI chat transcripts* and `#chats`; `chats.dart` app tag; `devices_page.dart` kinds and the `/relay:connect` line. Widget tests.
- [x] 4.3 A Maestro flow in `mobile/device-check/flows/` that opens *AI chat transcripts* from Home and finds the steps.

## 5. Docs

- [x] 5.1 `plugin/README.md` and `site/src/content/docs/connections/claude-code.md` as numbered steps for Claude Code and Codex.
- [x] 5.2 `connections/connect-your-ai.md`, `connections/index.md`, `api/keys.md`, `api/connect-a-service.md`, and the app pages that name *Claude Code chats* or the old connector address.
- [x] 5.3 `wiki/stack/relay-ai-connector.md` and `wiki/stack/relay-chats.md`; `scripts/product-name.test.mjs` lists the new skill files.

## 6. Review fixes

- [x] 6.1 Codex's sandbox: each skill tells Codex to run its command outside the sandbox, with the person's approval; `plugin/README.md` and `connections/claude-code.md` say this step for Codex. `lib/sandbox.mjs`: a failed fetch (`EAI_AGAIN`, `ENOTFOUND`) or write (`EROFS`, `EACCES`) names a sandbox in `connect.mjs start`, `relay.mjs` and `save.mjs`; `start` says when it can not write its folder; `saving.mjs` with no choice reads the state where it can not write. Tests.
- [x] 6.2 `relay.mjs`: a 401 or 403 shows the server's own reason (`error_description` from `/v1`, `error.message` from the app's routes); the chat-key line only when the server sends it. The test's fake server sends the real status and words.
- [x] 6.3 `connect.mjs wait`: a link still `waiting` after `startedAt + LINK_LIFE` ended (its waiter died): it says to start again with /relay:connect. Test.
- [x] 6.4 `connect.mjs`: in a folder it can not write, `wait` still gives its answer, such as *connected as "…"*, when only the clean-up fails; the command line catches a failed `start`, `wait`, `status` or `forget` and prints one line, with the sandbox line, not a Node stack. Tests.

## 7. Checks

- [x] 7.1 Local: `npm test` in `app/`, `node --test plugin/test/`, `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`.
- [ ] 7.2 `/save`, then wait for CI, `flutter test` included, and the preview.
- [ ] 7.3 On staging, from this computer, in a separate `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `RELAY_EVERYTHING_HOME` (nothing in the real setups): install the plugin from GitHub at this branch in Claude Code and in Codex, Codex with its default `workspace-write` sandbox and no bypass, approving each command to run outside the sandbox; `/relay:connect https://app-staging.relayeverything.com`, confirm the link with the staging session; a Claude Code chat and a Codex chat each show on staging with their app; *what did I note …?* answers a seeded note in both; *save this* adds a summary; saving off sends nothing; a fake `relay` connector is pointed out and not removed unasked. Write the steps into the plugin's docs where they differ.
- [ ] 7.4 `node scripts/relay-mcp-trial.mjs --staging` against `https://mcp-staging.relayeverything.com`, and an MCP `initialize` with a token on both `/` and `/mcp`.
- [ ] 7.5 The iPhone device check with the new flow.
