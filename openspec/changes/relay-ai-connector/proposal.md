# Connect Relay to your AI

## Why

Relay holds your notes, health and places, but to ask a question about them you must open the Relay page and look. With one connector address, you ask your AI chat app instead: *what did I note at the bench last week?* or *how did I sleep on the days I wrote about the PCB?*

## What Changes

- **One address for any AI chat app.** You paste Relay's connector address into the Claude app, Claude Desktop, ChatGPT or Claude Code. The app sends you to your usual Relay sign-in once. After that, every chat in that app can read your Relay data when you ask.
  ```mermaid
  sequenceDiagram
    participant You
    participant AI as "Your AI app"
    participant R as "Relay connector"
    You->>AI: "Paste the address"
    AI->>R: "Connect"
    R->>You: "Relay sign-in"
    You->>R: "Approve"
    You->>AI: "What did I note on Tuesday?"
    AI->>R: "Search notes"
    R->>AI: "3 notes, with places"
  ```
- **Your AI can read, but never change.** It can search your notes, read one note, see a day's summary, see health over a time range, and see the places you went. It cannot add, edit or delete anything.
  | What you ask | What Relay gives the AI |
  |---|---|
  | *What did I say about the stiffener?* | the matching notes, with time and place |
  | *What did I do on Tuesday?* | that day's notes, steps, sleep and places |
  | *How did I sleep this month?* | sleep each night |
  | *Where was I when I wrote this?* | the note's place and the places near that time |
- **Only you can connect.** The sign-in admits only your Relay login. A phone's device key cannot open the connector. Nothing else on your site opens to the internet.
- **You see and remove connected apps on the Relay page.** A *Your AI* card shows the address to copy, each connected app, and *Disconnect*. Disconnect stops that app at its next question; you can't undo it, so you connect again to get it back. This sketch is not a real picture: the Relay page is still being built in another chat.
  ```screen
  <div class="card col gap">
    <div class="row gap"><h3>Your AI</h3><span class="grow"/><span class="tag-outline">2 connected</span></div>
    <span class="muted">Paste this address into your AI app's connectors.</span>
    <div class="row gap"><span class="field grow">https://relay-ring-mcp.example.workers.dev/mcp</span><button class="btn-primary">Copy</button></div>
    <div class="sep"/>
    <div class="row gap"><span class="grow">Claude</span><span class="muted">Connected Nov 5</span><button class="btn-ghost">Disconnect</button></div>
    <div class="row gap"><span class="grow">ChatGPT</span><span class="muted">Connected Nov 6</span><button class="btn-ghost">Disconnect</button></div>
  </div>
  ```
- **Your health and places go to the AI company only when you ask.** The AI reads only what a question needs, and that part goes to the AI company's servers. Relay keeps the rest in your Cloudflare account. Notes you keep offline on your phone never reach Relay, so the AI never sees them.

This build starts after the Relay app first version publishes; the chat "Set up the Relay ring repo" builds it.

Non-goals: saving AI chats (the Relay plugin, planned in its own workspace, does that and can bundle this address), writing notes from the AI, playing recordings in the AI, connecting other people, and reading Relay from this project's own chats.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`. The build first checks that it can make an Access sign-in, a KV store and a Worker.
- **AI apps to try it in**: Later. A script tries the test copy before publish; your own try in the Claude app and ChatGPT is an open thread for after it.

## Capabilities

### New Capabilities
- `relay-ai-connector`: a remote MCP server (Streamable HTTP) with OAuth 2.1, admitting only the owner, that exposes read-only tools over Relay's notes, health and locations, plus a list of connected AI apps that the owner can revoke.

### Modified Capabilities
None.

## Impact

- New: a second Worker `relay-ring-mcp` (`app/worker/relay-mcp/`, `app/wrangler.relay-mcp.jsonc`) with its staging copy; a KV namespace for OAuth grants per environment; an Access for SaaS (OIDC) application per environment; Worker secrets for the OIDC client and cookie key.
- Changed: `app/worker/apps/relay/` (shared read queries, the *Your AI* routes), `app/src/apps/relay/` (the *Your AI* card), `app/wrangler.jsonc` (a service binding to the connector), `scripts/cf-deploy.sh` (deploy the connector on publish, as the line Worker is), the relay wiki page.
- Dependencies: `@cloudflare/workers-oauth-provider`, `agents` (MCP handler), `@modelcontextprotocol/sdk`.
- Data: no new table, no change to Relay's tables.

## Decision log

- **2026-11-05** — Asked which AI should reach Relay's data → chose any chat app: one connector address with its own sign-in.
- **2026-11-05** — Asked what the AI may read → chose notes, health and places.
- **2026-11-05** — Asked (Matthew, unprompted) for fully offline notes as the default, with sending out as an add-on → opened the workspace "Relay offline notes by default" for it; this connector reads only what reached Relay's server.
- **2026-11-05** — Asked (Matthew, unprompted) that health data stay in the health app when not synced → passed to the offline-notes workspace; no change here.
- **2026-11-05** — Asked which AI app to try before publish → chose both the Claude app and ChatGPT.
- **2026-11-05** — Asked what to do while the Relay server is unpublished → chose: ship this unasked once the Relay app first version publishes.
- **2026-11-05** — Asked whether Relay data is encrypted end to end → chose no: data is kept on Relay's server or only on the phone, and the server may be open-sourced later so people can run their own; so the connector reads data on the server.
- **2026-11-05** — Asked how AI chats get into Relay → chose a plugin: it holds the save tool and a hook, and can set up a self-hosted server; opened the workspace "Relay plugin for saving AI chats". This connector stays read-only.
- **2026-11-05** — Asked when to set up the live connector, which the site must find at its first deploy → chose just before publish, after the trial on the test copy passes.
- **2026-11-05** — Assumed: the connector is its own small Worker on its own address, not new public paths on the main site, because a sign-in that chat apps can reach must be open to the internet, and a separate Worker keeps the main site fully behind its login.
- **2026-11-05** — Assumed: WongStack's company actions are not used, because they reach only an assistant running in this project's folder, and the person chose any chat app.
- **2026-11-05** — Assumed: the sign-in is Cloudflare Access acting as the login for the connector (Cloudflare's documented pattern), because it reuses the login Matthew already has and adds no password.
- **2026-11-05** — Assumed: the AI gets tools only, all read-only, with no recordings, because chat apps can't play audio and the person asked to read data.
- **2026-11-05** — Assumed: days and times use Toronto time unless a question names another zone, because Relay's seed places and its owner are in Toronto.
- **2026-11-05** — Assumed: note search matches words in the text, with no new search index, because one person's notes stay small enough to scan.
- **2026-11-05** — Assumed: a staging copy reads staging's made-up data, so the connector can be tried in a real AI app before publish.
- **2026-11-05** — Assumed: the disconnect route is `POST ai-apps-disconnect` with the id in its body, not `DELETE ai-apps/<id>`, because the app router matches whole routes and has no path parameter.
- **2026-11-05** — Assumed: `/authorize` shows a short consent page that names the AI app before the Access sign-in, through the OAuth library's consent helpers, because an open registration endpoint otherwise lets any app ride the owner's Access session; the helpers' own cookies replace `COOKIE_ENCRYPTION_KEY`.
- **2026-11-05** — Assumed: the tools run on the MCP SDK's own web transport, without the `agents` package, because `agents` could not install beside this app's packages (a peer version conflict).
- **2026-11-05** — Assumed: the sign-in store gets no id in git; the first deploy, which setup runs with the user token, makes it, because the CI deploy token can't make a store and later deploys keep the Worker's own.
- **2026-11-05** — Assumed: the publish deploys the connector before the app, not after, because Cloudflare refuses a deploy whose service binding names a Worker that does not exist.
- **2026-11-05** — Assumed: the connector's address is a var on the connector, which `Grants.list()` returns, because the main app's answer check treats an unknown long env string as a possible credential.
- **2026-11-05** — Assumed: only the owner (and the checker on staging) reaches the AI apps routes; where `RELAY_MCP` is not bound, such as a local run, they answer 503 and the card says the connector is not set up.
- **2026-11-05** — Assumed: `places` returns each stay at a place as one visit, and `health` hour buckets are UTC hours, because a stay is what "where was I" asks and a zone's hour boundaries match UTC's for whole-hour zones.
- **2026-11-05** — Assumed: `scripts/check-private-access.mjs` needs no change: an Access for SaaS app has no Worker destination and its domain is the team domain, so `accessConflicts` never matches it, and `checkPolicies` reads only the main app's policies. A test now proves it.
- **2026-11-05** — Check: `app/knip.jsonc` adds `worker/relay-mcp/index.ts` as an entry, because it is its own Worker's entry (`wrangler.relay-mcp.jsonc`), like the live line's; knip still checks every file it imports.
- **2026-11-05** — Check: `app/knip.jsonc` ignores the dependency name `cloudflare`, because knip reads the `cloudflare:workers` runtime module, which the connector's `Grants` entrypoint needs, as an npm package; no npm package of that name is used.
- **2026-11-05** — Check: `app/vitest.config.ts` maps `cloudflare:workers` to a stand-in and runs `@cloudflare/workers-oauth-provider` through Vite, because that module exists only in the Workers runtime; no test or threshold is skipped.
- **2026-11-05** — Assumed: setup runs for staging before the save and for production just before the merge, because the save's preview binds `relay-ring-mcp-staging` and the publish's deploy needs `relay-ring-mcp` and its sign-in store; tasks 5.1 to 5.3 follow this order.
- **2026-11-05** — Assumed: the check before publish is a script, `scripts/relay-mcp-trial.mjs`, not a try by hand in the Claude app and ChatGPT; Matthew's own try in both apps is an open thread for later.
- **2026-11-05** — Assumed: the trial does not sign in with the checker's service token, because the connector's second lock admits only the owner's email and a service token has none, and a service-token rule on the sign-in app would widen the first lock. With no person, it checks each step up to the Access sign-in and every refusal; `--sign-in` adds one owner sign-in in a browser on this computer.
- **2026-11-05** — Assumed: an app in use stays connected: `refreshTokenIdleTTL` of 30 days moves a sign-in's end at each refresh, so it drops after 30 days unused.
- **2026-11-05** — Assumed: the wiki gives the deploy command to put a branch's connector code on staging, not setup deploying each run, because a setup run for production would then deploy the branch's code live.
- **2026-11-05** — Assumed: setup's permission check also needs "Access: Organizations, Identity Providers, and Groups Read" (or its Write), for `GET /accounts/{id}/access/organizations`, by Cloudflare's API reference.
- **2026-11-05** — Assumed: a `timeline` or `search` cursor never reads past `to`: the page starts at the earlier of the cursor and the range's end.
- **2026-11-05** — Assumed: setup takes Cloudflare's API, wrangler and its output as arguments, so a test runs the real setup path against stand-ins and checks that no secret value is printed.
