# Run your own Relay server

**Status:** ready-to-ship
**Branch:** quaint-hound
**Open questions:** none

## Why

Relay's point is that your notes, health, places and AI chats go to a place you choose and stay yours. Today the only Relay server is Matthew's. Now that Relay is open source, anyone can run their own server in their own Cloudflare account, with one request to their AI. Relay's apps then only add data to it: they can't read it back, so the data belongs to the person who owns the server.

## What Changes

- **Run your own Relay with one request to your AI.** You paste one request into Claude Code or another coding AI. It follows Relay's setup guide: it gets a Cloudflare key from you, makes your server in your own Cloudflare account, and gives you its address. Cloudflare's free plan is enough. Your login is your own email.
  ```text
  Install Relay from
  github.com/matthewwong525/RelayEverything.
  Read and follow self-host/SETUP.md there.
  ```
  ```mermaid
  flowchart TD
    A["Paste the request"] --> B["Make a Cloudflare key"]
    B --> C["AI makes your server"]
    C --> D["Your address and login"]
    D --> E["Keys for each device"]
  ```
- **You get Relay, not WongStack.** The install has only Relay's parts. It does not add the AI workflow, wiki, memory store or check runner that this project uses to build Relay.
  | Your install has | Your install does not have |
  |---|---|
  | Relay's server: notes, recordings, health, places, AI chats | WongStack's skills, wiki and memory store |
  | The Relay page, behind your own login | The check runner and previews |
  | Device keys for each phone, Pebble and Claude Code | Cloudflare's paid plan |
  | The AI connector, so your AI reads your data | Matthew's server or data |
- **Your devices send to your server, and can't read it.** Each phone, the Pebble app and the Claude Code plugin gets a key that only adds data. It can't list, read or delete anything. This is true on Matthew's server too. Phone keys now work the way the plugin's chat keys already do. **BREAKING:** an older phone app can't show ring notes after this change; update the app when it goes live.
  | Key | Can add | Can read, list or delete |
  |---|---|---|
  | A phone | typed notes, health, places | nothing |
  | The Pebble app | ring notes and their recordings | nothing |
  | Claude Code | chats | nothing |
  | You, signed in | — | everything, on the Relay page |
- **You read on your Relay page and with your own AI.** You sign in to your Relay page with your email, on any computer or phone browser. Your AI reads through your own AI connector address. Relay, the company, has no way in.
  ```mermaid
  flowchart TD
    P["Phone"] -->|"adds"| S["Your Relay server"]
    R["Pebble"] -->|"adds"| S
    C["Claude Code"] -->|"adds"| S
    S --> W["Your Relay page, your login"]
    S --> A["Your AI connector"]
  ```
- **The phone shows its own notes and opens your page for the rest.** The phone's list shows the notes you typed on it. Ring notes and recordings are on your Relay page; a button opens it. Connecting a phone checks its key without reading any data.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3 class="grow">Notes</h3><button class="btn-ghost">Settings</button></div>
    <div class="card col gap"><span>Ring notes and recordings are on your Relay page.</span><div class="row gap"><span class="grow"/><button class="btn-ghost">Open your Relay page</button></div></div>
    <span>Call the battery supplier about the 40 mAh cell</span>
    <span class="muted">Today 9:41 · Typed · Sent</span>
    <div class="sep"/>
    <span>Buy 0.2 mm steel for the stiffener</span>
    <span class="muted">Yesterday · Typed · Waiting to send</span>
    <div class="row gap"><span class="grow"/><button class="btn-primary">New note</button></div>
  </div>
  ```
- **Make keys and update from your own computer.** You make each device's key with one command in your copy of Relay. It shows the key once, as a QR code. To get a newer Relay, you ask your AI *update my Relay*: it gets the latest code, updates your database and puts the new server live. Your data stays.
  ```text
  $ node scripts/relay-device-key.mjs create --name "iPhone"
  Server: https://relay.your-name.workers.dev
  Scan this QR code in the Relay app.  (shows once)
  ```
- **The website tells you to run your own.** A new page, *Run your own Relay server*, gives the request to paste, what it costs, and what you get. *What you need*, *Connect a phone*, *Keys*, *Recordings*, *Notes* and *Privacy* change to match. The install carries what the *Connections* pages tell: webhooks to *Your own database*, *Connect your AI* and *Claude Code*. The home page points to it.
  ```screen
  <div class="card col gap">
    <h3>Run your own Relay server</h3>
    <span>Your server, in your own Cloudflare account. Relay's apps only add to it.</span>
    <span class="field">Install Relay from https://github.com/matthewwong525/RelayEverything. …</span>
    <span class="muted">Free on Cloudflare's free plan · about 10 minutes · your email is your login</span>
    <div class="row gap"><span class="tag">Server</span><span class="tag">Relay page</span><span class="tag">Device keys</span><span class="tag">AI connector</span></div>
  </div>
  ```

The Cloudflare rename, webhooks, the AI connector, the Claude Code plugin and offline notes are live, and the install carries what each adds.

Non-goals: Relay hosting servers for other people, end-to-end encryption, moving data from one Relay server to another, a second test copy (preview) of a person's own server, and other hosts than Cloudflare.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`. The build makes a test install in your account under its own names, sends to it from a phone and the plugin, then removes it.
- **Your iPhone**: Ready, you have it. After this is live, you connect it to a test install and send a note; that check waits for you and does not hold up the publish.
- **The other Relay changes first**: Ready, nothing from you. They are live.

## Capabilities

### New Capabilities
- `relay-self-host`: a Relay-only install in a person's own Cloudflare account, made and updated by an AI following `self-host/SETUP.md` and a deterministic setup script, holding the Relay server, the Relay page behind the person's own Access login, device keys and the AI connector, and none of WongStack.

### Modified Capabilities
- `relay-device-keys`: device keys become send-only: they reach only the routes that add data, plus a key check that returns no data.
- `relay-website`: the docs gain a self-host page and say that devices only send.

## Impact

- New: `self-host/` (`SETUP.md` for the AI, `setup.mjs` with `check`, `install`, `update`, `status` and `remove`, the server and connector templates, tests); a Relay-only Worker entry and a Relay-only page build in `app/`; `GET key` route; the website page *Run your own Relay server*.
- Changed: `app/worker/apps/relay/device.ts` (send-only reach), `scripts/relay-device-key.mjs` (reads a self-host install's config), `mobile/` (no server timeline or recordings, key check, *Open your Relay page*), `site/` pages, the API reference, `AGENTS.md` (device-key line), `wiki/open-source.md`.
- Systems: each install makes, in the person's account, the `relay` Worker, the `relay-db` database, the `relay-notes` bucket, the `relay-webhooks` queue, the `relay-mcp` connector Worker with its sign-in store, two Access apps, and a Pebble signing secret. Matthew's server keeps its names: `relay-everything`, `relay-everything-db`, `relay-everything-notes`, `relay-everything-webhooks` and `relay-everything-mcp`, at `app.relayeverything.com`.
- Dependencies: none new.

## Decision log

- **2026-11-05** — Settled by Matthew: no end-to-end encryption; "we just encourage people to self host".
- **2026-11-05** — Settled by Matthew: the server is something the person owns; Relay's clients "interface and write to it with no read".
- **2026-11-05** — Asked how the repo goes to GitHub → chose move the home to GitHub. Done by Matthew before this plan was written: RelayEverything is public under MIT (b355538), so this plan opens no repository.
- **2026-11-05** — Asked which license → chose MIT. Done in b355538.
- **2026-11-05** — Asked how a person sets up their own Relay → chose "install like wongstack but it shouldn't install wongstack, only the relay component … so that it works with the plugin".
- **2026-11-05** — Asked what the Relay-only install holds → chose the server, the Relay page, device keys and the AI connector; no WongStack skills, wiki, memory store or checks.
- **2026-11-05** — Asked what the phone's key may do on your own server → the orchestrator chat, for Matthew, chose memory #46: send-only. Phone keys only add data, on every Relay server.
- **2026-11-05** — Assumed: send-only applies to Matthew's server too, not only to self-hosted ones, because one key shape keeps one set of routes, docs and tests.
- **2026-11-05** — Assumed: the phone app and the send-only server go live in one publish, with no grace period for older apps, because Matthew is the only person with the app today and updates it at the same time.
- **2026-11-05** — Assumed: the phone checks a key with a new `GET key` route that answers only the key's own device name, because connecting used the timeline, and a name is no data.
- **2026-11-05** — Assumed: the install's login and device keys use Cloudflare Access in the person's account, as Matthew's does, because the Relay page needs a login, the free Zero Trust plan covers 50 people, and the apps and key command stay as they are.
- **2026-11-05** — Assumed: one code for both servers: the install deploys the same Relay files from `app/` through a Relay-only entry, not a copy, because a second copy goes stale.
- **2026-11-05** — Assumed: the setup is a guide for the AI (`self-host/SETUP.md`) over a deterministic script (`self-host/setup.mjs`), because the steps repeat for every person and a script runs them the same way each time.
- **2026-11-05** — Assumed: the install runs on Cloudflare's free plan, because Workers, D1, R2 and Access all have free tiers; the build checks each one, and the guide says so if a part needs the paid plan.
- **2026-11-05** — Assumed: the person's install has no preview copy, because one person's own server needs no test copy; updates apply database changes before the new code goes live.
- **2026-11-05** — Assumed: the install's settings live in the person's clone, in a git-ignored `self-host/install.json`, and the key command reads it when it is there, because the key command already lives in the repo.
- **2026-11-05** — Assumed: a test keeps the install's bindings equal to the Relay bindings in `app/wrangler.jsonc`, because a later Relay change, such as webhooks' queue, would else break installs.
- **2026-11-05** — Assumed: this build waits for the rename, webhooks, connector, plugin and offline changes, because the orchestrator chat said the rename and webhooks touch the same code and ship first, and the install carries what the others add.
- **2026-11-05** — Assumed: the plan follows the rename to `relay-everything` and reuses the plugin's `reaches` for phone keys, not a copy, because the orchestrator chat asked for both after the rename and the plugin went live.
- **2026-11-05** — Assumed: the install keeps its settings in git-ignored `self-host/wrangler.jsonc` and `self-host/wrangler.mcp.jsonc`, not a separate `install.json`, because the key command and wrangler both read a wrangler config already.
- **2026-11-05** — Assumed: `check` tries each Cloudflare part instead of reading the token's own permission list, because a new person's token may not read itself, and a try also finds R2 or Zero Trust turned off.
- **2026-11-05** — Assumed: `install` makes the Pebble signing secret and shows it only on a private page, because a person's own server has no one else to give it.
- **2026-11-05** — Assumed: the iPhone check on a test install goes in an open thread and does not hold up the publish, because the orchestrator chat said steps only Matthew can do on a device wait for him.
- **2026-11-05** — Built: send-only keys with `GET key`, the phone without server reads, the Relay-only Worker and page, `self-host/` with its guide, script and tests, and the website pages. App and website checks pass here; the phone's tests run first in CI, since Flutter is not on this computer. Next: the test install, then publish.
- **2026-11-05** — Check: `app/knip.jsonc` adds `worker/relay-only.ts` and `src/relay-only.tsx` as entries, loosening nothing, because they are the install's own Worker and page entries, which no other file imports.
- **2026-11-05** — Check: `app/package.json` adds `build:relay-only` and runs `../self-host/*.test.mjs` in `npm test`, loosening nothing, because the install's build and its tests must run in CI with the app's.
- **2026-11-05** — Tested: a test install, `relay-selfhost-test`, in Matthew's account. Its device key checked itself and added a note; reading the timeline or summary got 403; with no key, the page sent to the login. `remove --yes` left nothing. The test found three fixes, now in `setup.mjs`: the build names its folder with underscores, so the deploy reads the build's redirect file; the login covers the Worker itself, as Matthew's does; and `remove` detaches the queue's reader before it deletes the Worker, then the queue.
- **2026-11-05** — Checked on the preview: a new preview phone key checked itself and added a note; reading the timeline or a recording got 403. The key was then turned off. Matthew's own iPhone check on a test install stays an open thread.
- **2026-11-05** — Archived for publish on branch quaint-hound, with the test install's three fixes to `setup.mjs`.
