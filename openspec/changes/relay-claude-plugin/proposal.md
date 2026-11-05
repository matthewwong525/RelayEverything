# Save your Claude Code chats to Relay

**Status:** in-progress
**Branch:** afraid-cheetah
**Open questions:** none

## Why

Your notes, health and places go to Relay, but your work with an AI does not: a chat's decisions and ideas stay on one computer, and you lose them when the chat closes. A Relay plugin for Claude Code keeps each chat in Relay, word for word, beside your notes, so you can read it again on the Relay page or ask your AI about it later.

## What Changes

- **Install once, then every chat is saved.** You add the Relay plugin to Claude Code and paste one connect code from the Relay page. After that, each Claude Code chat on that computer goes to your Relay server as it happens. It sends only the new part after each reply, and once more when the chat ends. A chat that could not be sent, because the computer was offline, goes at the next start.
  ```mermaid
  sequenceDiagram
    participant You
    participant P as "Plugin"
    participant R as "Relay"
    You->>P: "Paste connect code"
    You->>P: "Chat, get a reply"
    P->>R: "New messages"
    You->>P: "Close the chat"
    P->>R: "Last messages"
  ```
- **Your words and the AI's replies are kept exactly; the steps are kept short.** Each step the AI takes is one line, such as *Ran the tests* or *Edited app/notes.ts*. The plugin does not send the AI's tool output, the files it read, or its private reasoning. Text that looks like a key or a password is replaced with *[hidden]* before it leaves your computer.
  | In the chat | What Relay keeps |
  |---|---|
  | Your message | word for word |
  | The AI's reply | word for word |
  | The AI runs a command | *Ran: npm test* |
  | The AI reads or edits a file | *Read app/notes.ts*, *Edited app/notes.ts* |
  | Tool output, file contents, private reasoning | nothing |
  | A key in any of the above | *[hidden]* |
- **Keep a project out.** Saving is on in every project. You type `/relay:saving off` in a project to stop saving chats there, and `/relay:saving on` to start again. `/relay:saving` tells you what it does in this project and when it last sent.
  ```text
  > /relay:saving off
  Relay won't save chats in this project (relay-ring).
  Turn it back on with /relay:saving on.
  ```
- **Ask the AI to save something now.** Say *save this to Relay*. The AI sends the chat so far, plus a title and a short summary it writes. Relay marks that summary *Written by the AI*, because it is the AI's own words, not the chat.
  ```text
  > Save the plan for the stiffener to Relay
  Saved to Relay: "Stiffener plan",
the chat so far and a summary.
  ```
- **A Chats list on the Relay page.** It shows each saved chat, newest first, with its title, project, day and length. You can search the words of every chat. You open a chat to read it as it happened. *Delete* removes a chat from Relay; you can't undo it. This sketch is not a real picture: the Relay page is still being built in another chat.
  ```screen
  <div class="card col gap">
    <div class="row gap"><h3>Chats</h3><span class="grow"/><button class="btn-ghost">Connect Claude Code</button></div>
    <input class="field" placeholder="Search your chats"/>
    <div class="row gap"><span class="grow">Stiffener plan</span><span class="tag">Saved by the AI</span></div>
    <span class="muted">relay-ring · Today 9:41 · 38 messages</span>
    <div class="sep"/>
    <div class="row gap"><span class="grow">Fix the Pebble webhook signature</span></div>
    <span class="muted">relay-ring · Yesterday · 112 messages</span>
    <div class="sep"/>
    <div class="row gap"><span class="grow">Pick a battery for the ring</span></div>
    <span class="muted">relay-cad · Nov 3 · 54 messages</span>
  </div>
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">Back</button><h3 class="grow">Stiffener plan</h3><button class="btn-ghost danger">Delete</button></div>
    <span class="muted">relay-ring · Today 9:41 · Claude Code</span>
    <div class="card col gap"><span class="tag-outline">Written by the AI</span><span>Use a 0.2 mm steel stiffener under the battery, glued, not soldered.</span></div>
    <span class="muted">You</span><span>How thick should the stiffener be?</span>
    <span class="muted">AI</span><span>0.2 mm is enough for a ring this size. Here is why…</span>
    <span class="muted">Read pcb/relay.kicad_pcb</span>
    <span class="muted">You</span><span>Save the plan for the stiffener to Relay</span>
  </div>
  ```
- **A Connect Claude Code dialog.** It shows the two commands to install the plugin and the one command that makes a connect code on this computer. A connect code made for Claude Code can only add chats. It can't read, change or delete anything on the server, your chats included.
  ```screen
  <div class="card col gap">
    <h3>Connect Claude Code</h3>
    <span>1. Make a connect code on the computer that holds Relay's keys:</span>
    <span class="field">node scripts/relay-device-key.mjs create --name "Laptop" --for claude-code</span>
    <span>2. In Claude Code, add the plugin:</span>
    <span class="field">/plugin marketplace add matthewwong525/RelayEverything</span>
    <span class="field">/plugin install relay@relay</span>
    <span>3. Paste the connect code when Claude Code asks.</span>
    <span class="muted">Chats from then on are saved. Older chats are not sent.</span>
    <span class="muted">To keep chats in your own account, run your own Relay server and make the code there.</span>
    <div class="row gap"><span class="grow"/><button class="btn-primary">Done</button></div>
  </div>
  ```
- **Your AI can read your saved chats.** The Relay AI connector gets two more read tools: search your chats, and read one chat. You can then ask *what did we decide about the stiffener yesterday?* from Claude Code or any AI app you connected. The plugin can also add the connector to Claude Code for you: `/relay:connect-ai` takes the address on the *Your AI* card.
  | What you ask | What Relay gives the AI |
  |---|---|
  | *What did we decide about the stiffener?* | the matching chats, with the lines that match |
  | *Show me yesterday's chat about the webhook* | that chat's messages, a part at a time |
- **The plugin's code can be public; your chats are not.** The plugin lives in the public Relay repository, and you add it to Claude Code from there. So the plugin holds no key and no address. Your chats stay on your Relay server in your Cloudflare account. When you ask your AI about a chat, the part it reads goes to that AI company.
- **Works with your own Relay server too.** The connect code holds the server's address, so the plugin sends to whichever Relay server made the code: Relay's, or one you run yourself. The plugin's page and the *Connect Claude Code* dialog say so, and suggest that you run your own server to keep your chats in your own account.
  ```text
  Want your chats only in your own account?
  Run your own Relay server, then make the
  connect code there. The plugin works the same.
  ```
- **A Claude Code page on the Relay website.** The website's Connections section gets a *Save Claude Code chats* page with the same steps, what is sent, and how to turn saving off. It writes `<your-relay-server>` for the address.
- **A Connect your AI page on the Relay website.** The AI connector is live, but the website has no steps to add it. A *Connect your AI* page under Connections, next to *Save Claude Code chats*, gives the steps for the Claude app, ChatGPT and Claude Code, what the AI can read, and how to disconnect. It writes `<your-relay-server>` for the connector's address.

The Relay app first version is live. This build starts after the AI connector publishes (the workspace "SHIP: Relay MCP server").

Non-goals: setting up your own Relay server (planned in the workspace "Self-host Relay on your own server"), saving chats from the Claude app, Claude Desktop or ChatGPT (they have no way to tell a plugin that a chat ended), sending chats from before the install, chats in the phone app, sending chats to your webhooks (the webhooks change adds them), and end-to-end encryption.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`. It makes the connect codes and the staging copy.
- **Claude Code to try it in**: Ready, Claude Code 2.1.310 is on this computer. The build installs the plugin from this repository, connects it to the staging server, and checks that a chat shows on the preview's Chats list.

## Capabilities

### New Capabilities
- `relay-chats`: Relay's server stores AI chats sent by a chat-only device key, shows them on the Relay page with search and delete, and offers them to the AI connector through read-only chat tools.
- `relay-claude-plugin`: a public Claude Code plugin that sends each chat to Relay through hooks, offers a save tool, turns saving off per project, hides key-shaped text, adds the AI connector on request, and holds no key or address.

### Modified Capabilities
None. The AI connector's chat tools are new requirements in `relay-chats`, because `relay-ai-connector` is not yet a main spec.

## Impact

- New: `site/src/content/docs/connections/claude-code.md` and `connect-your-ai.md`; `plugin/` (the `relay` plugin: hooks, a stdio MCP server for the save tool, skills, tests); `.claude-plugin/marketplace.json` at the repository root; a migration adding `relay_chats`, `relay_chat_messages`, `relay_chat_saves`, and a `reaches` column on `relay_devices`.
- Changed: `app/worker/apps/relay/` (chat routes, device-key reach), `app/src/apps/relay/` (Chats card, chat view, Connect Claude Code dialog), `scripts/relay-device-key.mjs` (`--for claude-code`), the connector's tools in `app/worker/relay-mcp/` and the shared `queries.ts`, the relay wiki page, the website's Connections page and its API reference.
- Dependencies: none new in the plugin (plain Node 20+); none new in the app.
- Data: chats are a new kind of private data on Relay's server; *Delete* removes one and can't be undone.

## Decision log

- **2026-11-05** — Settled by Matthew in the request: the plugin holds a save tool and a hook that saves each finished chat word for word, and can set up a self-hosted server; no end-to-end encryption.
- **2026-11-05** — Asked how to handle the self-host setup while the server is not open source → chose its own part, later; opened the workspace "Relay self-host setup".
- **2026-11-05** — Asked what a saved chat keeps → chose your words and the AI's replies word for word, each step as one short line, no tool output or file contents, key-shaped text hidden.
- **2026-11-05** — Asked which chats the hook saves → chose every chat on the computer, with an off switch per project.
- **2026-11-05** — Asked where to read saved chats → chose the Relay page and the AI connector, not the phone app.
- **2026-11-05** — Assumed: the hook sends new messages after each reply and once more at the end, not only at the end, because a long-lived chat may never end and a crash would lose it; each send carries only the new messages, so it stays small.
- **2026-11-05** — Assumed: the save tool sends the chat so far and stores the AI's title and summary on that chat, marked *Written by the AI*, not as a Relay note, because the notes table's kinds belong to the first version, and the chat keeps the summary with its source.
- **2026-11-05** — Assumed: the save tool refuses in a project where saving is off, and says how to turn it on, because *off* means the project stays out of Relay.
- **2026-11-05** — Assumed: a Claude Code connect code is a Relay device key that reaches only the chat routes, made by the existing device-key command with `--for claude-code`, because it reuses the phone's key and revoke flow and a chat key then can't read health or places.
- **2026-11-05** — Assumed: the plugin holds no Relay address; the connect code carries the server's address, because Relay's public pages never name the private site's address.
- **2026-11-05** — Assumed: the project shows by its folder name, not its full path, because a full path shows the computer's user name.
- **2026-11-05** — Assumed: the hook skips a chat with no typed message, such as a background run, because it holds nothing you said.
- **2026-11-05** — Assumed: the connector gets two new tools, not chat results inside its `search` and `fetch`, because that keeps the connector's tested answers unchanged.
- **2026-11-05** — Assumed: the Chats list has *Delete*, because a private chat may be saved before you turn a project off.
- **2026-11-05** — Asked (Matthew, after the first draft) to make the plugin mandatory and enforce end-to-end encryption → weighed it: an encrypted server can't search, show or pass data to the online AI connector, and Pebble notes arrive unencrypted. Matthew then asked for a server the person owns, written to with no read, and chose: "no encryption i guess we just encourage people to self host". The plan keeps no encryption.
- **2026-11-05** — Asked whether the phone app and Pebble notes should also go to the person's own server → chose yes, in a new workspace; opened "Self-host Relay on your own server". It replaces the closed "Relay self-host setup" workspace.
- **2026-11-05** — Assumed: this plan's part of self-hosting is only that the plugin sends to the server named in its connect code and says self-hosting is an option, because setting up the server is planned in "Self-host Relay on your own server".
- **2026-11-05** — Told by Matthew (through the "Relay Everything" chat) that this repository becomes one public monorepo, relay-app folds into it, and `publish-relay-app.mjs` goes away → the plugin lives in `plugin/` and installs from this repository, with no separate public repository or publish script. Today's names stay until the rename change moves them.
- **2026-11-05** — Assumed: the marketplace file sits at the repository root, because Claude Code adds a marketplace by repository name; Matthew can add it while the repository is private, through his own GitHub login.
- **2026-11-05** — Merged main: the repository is public as matthewwong525/RelayEverything (b355538) → the install command names that repository; `scripts/public-check.mjs` checks `plugin/` on every change, and the plugin's own test still refuses Relay addresses and emails, which that check does not cover.
- **2026-11-05** — Assumed (the orchestrator chat, for Matthew): the chat key is a send-only key, as the self-host decision says: it adds chats and saves, and can't list, read, change or delete. Its answer gives only how many messages that chat holds, so the plugin resumes without reading; a repeat never changes stored text, and the page shows the newest save's title instead of changing the chat.
- **2026-11-05** — Found in review: the list route and the send route share the path `chats`, so a gate by path alone would let a chat key list chats → the gate lets a chat key through only with `POST`, and the read routes refuse every device key.
- **2026-11-05** — Checked against the decision to drop a Relay memory platform: the plan stays, because chats are data from a device sent to the person's server and read through MCP, with plain word search and no processors, semantic search or plugin tables. Assumed: sending chats to webhooks waits for the webhooks change, which adds chats as one more kind.
- **2026-11-05** — Assumed: the change adds a *Save Claude Code chats* page to the website's Connections section and rebuilds the API reference, because each change to Relay's connections updates its website page in the same change.
- **2026-11-05** — relay-ai-connector is on main (PR #3) → the build starts; Status in-progress.
- **2026-11-05** — Asked by the orchestrator chat, for Matthew: add a *Connect your AI* page under the website's Connections, because the connector shipped with no website page → added to this change as task 6.3, with `<your-relay-server>` for every address.
- **2026-11-05** — Build, task 1.2: the merged names fit the design with one change of shape → `DEVICE_ROUTES` became `reaches(reach, method, path)` in `device.ts`, and `deviceGate` takes the method, so the gate checks a chat key's `POST`.
- **2026-11-05** — Assumed (build): `POST chats` is a bare route, not a contract action, because the contract turns a 413 into a 400 and drops `stored` from an error body. Its fields are on the website's *Save Claude Code chats* page, through `HAND_PAGES` in `api-doc.ts`.
- **2026-11-05** — Assumed (build): one send's messages go in as JSON parts of under 1 MB each, inside one batch, because D1 limits one bound value to 2 MB and a send may hold 4 MB.
- **2026-11-05** — Assumed (build): `GET chat` cuts a part at 600,000 characters as well as at `limit` messages, and its `next` is the last `seq` sent, so one answer stays under the contract's 4 MB output limit.
- **2026-11-05** — Assumed (build): the checker's service token can read chats on a preview, as it reads notes, so the check before publishing can see them; every device key is refused on the read routes.
- **2026-11-05** — Assumed (build): a chat key's connect code prints in the terminal only when the output is a terminal, and is always on the private page, so a log of the command never holds it.
- **2026-11-05** — Assumed (build): the plugin hides the memory store's key shapes plus private key blocks and Slack tokens, because `scan.mjs` lacks those two and is a WongStack file this change does not edit; the plugin's test fails when `scan.mjs` gains a shape the plugin lacks.
- **2026-11-05** — Assumed (build): no Relay wiki page held the Relay app, so task 6.1's section is a new page, `wiki/stack/relay-chats.md`, linked from the stack hub and from the connector's page.
- **2026-11-05** — Assumed (build): `npm test` in `app/` also runs `node --test ../plugin/test/*.test.mjs`, so CI gates the plugin; a change to `plugin/` already runs the suite.
- **2026-11-05** — Assumed (build): the website's *Keys* page gains a section, *A chat key*, and the `--for claude-code` row, because it lists what each key reaches.
- **2026-11-05** — Assumed (build): the save tool sends the chat whole again when the server answers 404 for the save, as after the chat was deleted there; a deleted chat that is still open is sent again with the next message, and the docs say to turn saving off first.
- **2026-11-05** — Assumed (build, review round 2): a send that finds a chat busy marks it `again`, and the send that holds the lock reads the chat again, up to 3 times, then leaves it pending for the next start, because the holder may have read the chat before the busy send's messages and must not clear that mark.
- **2026-11-05** — Assumed (build, review round 2): a file lock waits only while another hook holds it, at most 15 s (past the 10 s stale limit), and any other open error fails at once, so a data folder that can't be written never holds a hook or the save tool.
- **2026-11-05** — Check: `app/package.json` adds `../plugin/test/*.test.mjs` to the `node --test` step of `npm test`, because CI should gate the plugin as it gates the app; no check is loosened.
- **2026-11-05** — Saved after the build and two review rounds: the reviewer's 8 findings (a `!` command's output, a save after `/clear`, the end send while busy, parallel hook writes, the last-sent line, an empty chat on a refused send, a lost busy mark, a lock that retried forever) are fixed with tests. Left: the website preview (6.2) and the live check on the preview (7.2).
