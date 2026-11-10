# One Relay Everything plugin for Claude Code and Codex, the AI connector at mcp.relayeverything.com, and Other connections on the phone

**Status:** building
**Branch:** mcp-plugin-other-connections
**Open questions:** none

## Why

The AI connector has a long, hard-to-type address. The Claude Code plugin saves chats, but to read your notes it needs a second step: adding the AI connector, which puts 14 tools into every chat. It works only in Claude Code, and nobody has tried a full install from start to finish. On the phone, nothing says that you can also save your AI chats.

## What Changes

- **The AI connector moves to mcp.relayeverything.com.** You add just `https://mcp.relayeverything.com` to the Claude app, ChatGPT or any app that takes a connector, with nothing after it. The same address with `/mcp` on the end works too. Open the address in a browser and a short page says what it is. An app connected at the old address must connect again, once, because its sign-in belongs to that address. Every page and doc names the new address.
  ```text
  Before: relay-everything-mcp.matthewwong525
          .workers.dev/mcp
  After:  mcp.relayeverything.com
  ```

- **One plugin works in Claude Code and in Codex.** You install it from the same place in both apps, and it does the same things in both.
  ```text
  Claude Code                 Codex
  /plugin marketplace add     codex plugin marketplace add
    matthewwong525/             matthewwong525/
    RelayEverything             RelayEverything
  /plugin install relay@relay codex plugin add relay@relay
  ```

- **You connect a computer by signing in from a link.** Type `/relay:connect`, and the plugin shows a link and a short code. Open the link on any phone or computer, check that the code matches, and click **Connect**. The computer gets its own key, and you never copy or paste it. Claude Code and Codex on that computer share the one key. To use your own server, add its address to the command.
  ```mermaid
  sequenceDiagram
    participant C as Your computer
    participant R as Relay Everything
    participant Y as You, in a browser
    C->>R: Start, with a secret
    R-->>C: A link and a code
    Y->>R: Open the link, sign in
    Y->>R: Code matches: Connect
    C->>R: Done yet? (each few seconds)
    R-->>C: The computer's key
  ```

- **The plugin reads your Relay Everything through skills, with no connector.** Ask *what did I note yesterday?* or *how did I sleep this week?*, and the AI runs the plugin's read step. It reads your notes, health, sleep, workouts, places, calendar and saved chats, and adds a note when you ask. The skills add only a few lines to each chat, not 14 tools. A computer's key reads all your data, as an API key does: turn it off on your page if the computer is lost.
  ```text
  You: how did I sleep this week?
  AI:  (reads with the Relay Everything skill)
       Mon 7h 10m · Tue 6h 40m · Wed 7h 55m
  ```

- **The plugin points out a second copy of the connector.** If Claude Code or Codex on that computer also has the Relay Everything AI connector, `/relay:connect` says so, and the AI offers to remove it to save space. A copy that comes from your Claude app account can't be removed from the computer, so the AI tells you how to turn it off.
  ```text
  Relay Everything is connected as "Laptop".
  This computer also has the Relay Everything AI
  connector ("relay"). The plugin does the same
  job: remove it to save space?
  ```

- **Codex chats save too, as AI chat transcripts.** After each answer, the plugin saves the chat word for word, from Claude Code or from Codex, with the same hidden keys and the same per-project off switch. On your page, *Claude Code chats* becomes **AI chat transcripts**, and each chat shows which app it came from.
  ```screen
  <div class="card col gap">
    <div class="muted">Other connections</div>
    <div>Location</div><div>Health</div><div>Calendar</div><div>Photos</div>
    <div class="row gap"><b>AI chat transcripts</b></div>
    <div class="sep"></div>
    <div class="row gap"><span class="grow">Fix the sign-in test</span><span class="tag-outline">Claude Code</span></div>
    <div class="row gap"><span class="grow">Plan the trip budget</span><span class="tag-outline">Codex</span></div>
  </div>
  ```
  No real picture: this computer has no Flutter to build the web page; the build checks it in a browser on the preview.

- **The phone gets an *Other connections* section.** Below *On this phone*, Home shows *Other connections*, with one row: **AI chat transcripts**. It opens a page that says what it saves, gives the steps for Claude Code and Codex, and, when you're signed in, links to your chats on the web. The phone still can't read your chats.
  ```screen
  <div class="card col gap phone">
    <h3>Home</h3>
    <div class="muted">On this phone</div>
    <div class="card col gap"><div>Location</div><div>Health</div><div>Calendar</div><div>Photos</div></div>
    <div class="muted">Other connections</div>
    <div class="card col gap"><div class="row gap"><span class="grow">AI chat transcripts</span><span class="muted">›</span></div></div>
  </div>
  ```
  No real picture: the phone app builds only in CI, and this computer has no Flutter. The build checks it on an iPhone.

- **Clear steps, tried for real.** The plugin's own page and the website page say each step in order: install, connect, ask, turn saving off. Before publishing, the build installs the plugin from GitHub on this computer, in Claude Code and in Codex, against the test server. It connects, saves a chat, reads a note, and checks the connector at its new address. Your own account gets nothing.
  ```text
  1. Install the plugin      (one command)
  2. /relay:connect          (click Connect)
  3. Ask about your notes    (it just works)
  ```

## What the build needs

- **Cloudflare key**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`; relayeverything.com is already on the account, so the new address needs no other step.
- **Test-server sign-in**: Ready, `CF_ACCESS_STAGING_CLIENT_ID` is in `.env`, for the checker's sign-in on the test server.
- **Codex and Claude Code logins on this computer**: Ready, both are signed in.

## Non-goals

- No plugin for apps other than Claude Code and Codex; every other app uses the connector.
- No read of photos through the plugin: the web API has no photo route yet.
- No tick boxes for what a computer's key reads: it reads everything.
- No change to what the phone's own key reads: it still reads no chat.

## Capabilities

### New Capabilities

- `relay-agent-plugin`: the Relay Everything plugin for Claude Code and Codex: connect by link, save chats from both apps, read and add through skills, find a doubled connector.

### Modified Capabilities

- `relay-claude-plugin`: retired; `relay-agent-plugin` replaces it.
- `relay-ai-connector`: the connector's address is `https://mcp.relayeverything.com`, with `/mcp` kept as a second way in; apps connected at the old address connect again.
- `relay-device-keys`: a computer's key, made by signing in from a link, saves chats and reads through the web API.
- `relay-chats`: a chat records the app it came from; a computer's key may also save chats.
- `relay-web-app`: the left bar's *Claude Code chats* becomes *AI chat transcripts*, and each chat names its app.
- `relay-home-screen`: Home adds *Other connections* with *AI chat transcripts*.

## Impact

- `app/wrangler.relay-mcp.jsonc`: `routes` with `mcp.relayeverything.com` and `mcp-staging.relayeverything.com` as custom domains; `RELAY_MCP_ADDRESS` set to `https://mcp.relayeverything.com/`; `index.ts` answers MCP at `/` and keeps `/mcp`; `workers_dev` off. `app/wrangler.relay.jsonc` and `app/wrangler.jsonc`: `RELAY_MCP_CALLBACK` on the new address.
- `app/worker/apps/relay/sign-in/`: a new `computer.ts` (start, confirm page, poll), routed in `sign-in/index.ts`; a new directory table for pending computer sign-ins.
- `schema/migrations/` and `schema/space-migrations/`: a new key reach `agent` in `relay_keys` and `relay_devices`; an `app` column on `relay_chats`.
- `app/worker/apps/relay/caller.ts`, `space.ts`, `device.ts`, `chats.ts`; `app/worker/relay-mcp/` (`apiKeyCaller` takes `agent`, chats answer `app`).
- `plugin/`: no `.mcp.json`, `save-server.mjs`, `connect-ai` or `userConfig`; new `bin/connect.mjs`, `bin/relay.mjs` (read and add), skills `connect`, `ask`, `save`, `saving`; a Codex transcript reader; a shared key file outside the plugin.
- `mobile/lib/`: `screens/home.dart` and a new transcripts page; `web/shell.dart`, `web/chats.dart`, `web/devices_page.dart`.
- `site/src/content/docs/`: `connections/claude-code.md`, `connections/connect-your-ai.md`, `api/keys.md`, `api/connect-a-service.md`, the API reference; `plugin/README.md`; `wiki/stack/relay-ai-connector.md`, `wiki/stack/relay-chats.md`; `scripts/relay-mcp-trial.mjs`, `scripts/product-name.test.mjs`.
- `schema/seed.sql`: a computer device and a Codex chat.

## Decision log

**2026-11-10** — Assumed: "mcp.relayeverything.com" is the live connector's address and `mcp-staging.relayeverything.com` the test server's, by the pattern of app.relayeverything.com and app-staging.relayeverything.com.

**2026-11-10** — Asked what the phone's *AI chat transcripts* row opens → chose a setup page; the phone's key still reads no chat.

**2026-11-10** — Asked how the plugin and the connector work together → answered, in their own words, that the plugin has skills and needs no connector. So the plugin reads through the web API from skills, and has no connector of its own.

**2026-11-10** — Asked where the test chats go → chose the test server only, in a separate test setup; nothing is installed in this computer's real Claude Code or Codex.

**2026-11-10** — Told mid-planning that this is not only Claude Code but Codex too, or anything that takes a plugin or a connector → the plugin covers Claude Code and Codex, both tried on this computer; any other app uses the connector.

**2026-11-10** — Asked what a computer's key may read → chose everything, with no tick boxes.

**2026-11-10** — Asked how a computer gets its key → chose sign in by link.

**2026-11-10** — Asked whether to split the three pieces → chose one plan.

**2026-11-10** — Asked, in the first message, whether the plugin needs its own repository → no: the repository's `.claude-plugin/marketplace.json` already serves it. Tried on 2026-11-10: `claude plugin marketplace add matthewwong525/RelayEverything` and `codex plugin marketplace add matthewwong525/RelayEverything` both installed `relay@relay`, and Codex used a plugin skill.

**2026-11-10** — Assumed: a computer's key is a new reach, `agent`, not a wider `chats` reach, because each existing chat key was made with the promise that it can only add chats. An old chat key keeps saving, and the read step says to connect again to read.

**2026-11-10** — Assumed: the page's *Add a device → Claude Code* choice goes, because the link sign-in replaces it and works over SSH too; an old chat key still shows and can be turned off.

**2026-11-10** — Assumed: the plugin may name `https://app.relayeverything.com` as its default server, because it is a public address; another server is one argument to `/relay:connect`. The no-secrets check still refuses keys, emails and workers.dev addresses.

**2026-11-10** — Assumed: the key lives in one file in the person's own config folder, readable only by them, as `gh` and `wrangler` keep theirs, because Codex has no secure store for plugins and both apps on one computer should share one key.

**2026-11-10** — Assumed: the link page shows a short code that the terminal also shows, and warns to connect only a computer you just started on, because a link sent by someone else could otherwise give them a key that reads everything.

**2026-11-10** — Assumed: the save-with-a-summary tool becomes a skill too, so the plugin starts no connector of its own.

**2026-11-10** — Asked, in a note on the review page, why the address ends in `/mcp` and not the bare address → the connector answers at `https://mcp.relayeverything.com`, and `/mcp` still works there; a browser opening the address gets a short page.

**2026-11-10** — Assumed: apps connected at the old workers.dev address connect again, and the old address stops, replacing the earlier guess that it keeps answering. The connector ties each sign-in to one exact address (`resourceMetadata.resource` in `@cloudflare/workers-oauth-provider` 1.2.4 checks every token's audience against it), so the old grants can't carry over. Only the owner's own apps connect there today.

**2026-11-10** — Assumed (build): the computer's start is `POST sign-in/computer/start`, not `POST sign-in/computer`, because the person's *Connect* form posts to `sign-in/computer` and must keep the page's Origin check, while the start comes from a computer with no Origin.

**2026-11-10** — Assumed (build): `POST sign-in/computer/key` has no rate limit, because its 256-bit secret lives 10 minutes, and the waiter's ask every 3 seconds would pass the sign-in limit of 10 a minute.

**2026-11-10** — Assumed (build): `scripts/company-api.mjs` holds no connector address, so it does not change.

**2026-11-10** — Assumed (build): the computer device *Laptop* and the Codex chat are sample rows in `app/tests/relay-space-rows.sql`, not `schema/seed.sql`, because `schema/seed.sql` seeds only the shared directory; a person's devices and chats live in their own space, which the seed can't reach. The existing *Laptop* row becomes a computer's key (`agent`), and the new chat is a Codex chat.

**2026-11-10** — Assumed (build): self-hosted setup prints `connector=` with no slash at the end, the address a person adds, and keeps the slash only in `RELAY_MCP_ADDRESS`.

**2026-11-10** — Assumed (build): no plugin hook is `"async": true`, because Codex skips an async hook; each hook records the session, starts a detached send, and ends at once.

**2026-11-10** — Assumed (build): Codex runs a plugin hook only after the person trusts it (**Trust all and continue** at the next start, or `/hooks`), and again after an update changes a hook; with no trust it runs none and says nothing. The plugin's README, the website page and the wiki say the step. `/relay:connect` shows the trust line only in Codex, not in Claude Code.

**2026-11-10** — Assumed (build): the `ask` skill reads times in the computer's own time zone unless the person names another.

**2026-11-10** — Assumed (build): the doubled-connector check names an entry called `relay` or *Relay Everything*, or one on the host of the key's `api` or on `mcp.relayeverything.com`; a staging key's own `api` host covers staging.

- **2026-11-10** — Check: `plugin/test/no-secrets.test.mjs` allows `https://relayeverything.com`, `https://app.relayeverything.com` and `https://mcp.relayeverything.com`, not only the app's address, because the connector check names the connector's public address and the plugin's homepage is the website. Each is a public address that `site/` already shows; keys, emails and every other address are still refused.

**2026-11-10** — Assumed (build): a plugin that is not connected says so one time, as a `systemMessage`; a chat that ended before the connect is not sent, and the open chat sends whole at its next answer.

**2026-11-10** — Assumed (build): the plugin gets no icon for now.

**2026-11-10** — Assumed (build): the phone's *AI chat transcripts* page and the web's *Connect a computer* dialog warn: *The computer's key saves your chats and can read all your Relay Everything data. To stop it, turn it off in Devices.* The web button says *Connect a computer*, to fit the 360 px list header.

- **2026-11-10** — Check: `plugin/test/code.test.mjs` is deleted, because `lib/code.mjs`, the connect code it tested, is gone: `/relay:connect` replaces the code, and `plugin/test/connect.test.mjs` and `config.test.mjs` test the new way in.

- **2026-11-10** — Check: `plugin/test/save-server.test.mjs` is deleted, because `bin/save-server.mjs`, the plugin's own connector, is gone: the `save` skill replaces it, and `plugin/test/save.test.mjs` tests it.

**2026-11-10** — Assumed (review): the plugin's commands run outside Codex's sandbox with the person's approval, not inside it, because in the default `workspace-write` sandbox they can not reach the server or write the key folder. A failed fetch or write with a code a sandbox makes adds one line that names the sandbox.

**2026-11-10** — Assumed (review): `wait` calls a link still `waiting` after its 10 minutes *ended*, with its own line, not *Nobody clicked Connect*, because the person may have clicked Connect after the waiter died.

**2026-11-10** — Saved for the final checks: built, reviewed twice (four fixes: Codex's sandbox, a turned-off key's words, a link whose waiter died, `connect.mjs` in a folder it can't write), local checks pass. Left: CI, the staging trial in Claude Code and Codex, the connector trial on `mcp-staging`, and the iPhone check.

**2026-11-10** — Assumed: this save leaves the main specs as they are, and the archive in `/ship` applies the deltas, because only the archive's own sync deletes the retired `relay-claude-plugin` spec, and a hand sync first would leave the archive nothing to retire.

**2026-11-10** — Staging trials: the connector trial passed on `/` and `/mcp`, and the plugin trial passed in Claude Code and in Codex with its sandbox on. The first iPhone check failed at the new step: the *AI chat transcripts* row lay under the search bar, so the tap opened Search. The flow now centers the row first.
