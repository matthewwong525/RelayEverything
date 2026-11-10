# Your WongStack memory inside the Relay Everything plugin, saved in your space

**Status:** planned
**Branch:** relay-memory-plugin-plan
**Open questions:** none

## Why

Matthew likes his own WongStack memory and wants it in Relay Everything, but a plugin that needs a second plugin from a second shop is too complicated. Relay Everything's plugin can carry a copy of that memory, turned on by one setup choice, and save it in each person's space.

## What Changes

- **One setup choice: memory or not.** When you connect a computer, Relay Everything asks *Also remember things for you?* Say no, and the plugin does what it does today: notes, health, places, *around a moment*, and chat saving. Say yes, and it also runs your WongStack memory. Nothing else to install, in Claude Code or Codex.
  ```text
  /relay:connect
    Open the link and sign in… connected.
    Also remember things for you?
      Yes → memory saves facts in your space
      No  → notes, health, places, chats only
  ```

- **Your memory, saved in your space.** With memory on, in a repo with no memory of its own, the save check, the chat-start summary, search, and before-edit warnings work as in WongStack, and the facts go to your Relay Everything space. Facts are only added, never edited: a new fact replaces an old one, and the old one stays readable.
  ```mermaid
  sequenceDiagram
    participant M as Memory (in the plugin)
    participant R as Your Relay space
    M->>R: save "battery is 50 mAh"
    R->>R: add it, mark 40 mAh replaced
    M->>R: search "battery"
    R-->>M: 50 mAh (40 mAh kept as history)
  ```

- **One list of fact kinds.** New facts use WongStack memory's five kinds. Older facts keep their words, and each shows as its nearest new kind.
  ```text
  Old kind     Shows as
  open         thread
  preference   feedback
  fact, decision, plan   project
  reference    reference
  ```

- **Relay Everything keeps your life data.** Notes, health, places, and *around a moment* stay Relay Everything's own; memory never reads them. Memory gets your topics from Relay Everything, so a chat starts with them and a message that names one brings it in. When you pull a topic, Relay Everything adds its notes and chats beside memory's facts.
  ```text
  Pull "battery":
    page, linked topics, facts   ← memory
    notes, chats                 ← Relay Everything
  ```

- **A repo with its own memory keeps it.** In WongOS, this repo, or any WongStack install, the plugin's memory stays off, so team facts stay with the team and memory never runs twice. Notes, health, and places still work there.
  ```text
  Repo has memory?
    yes → the repo's memory; Relay's stays off
    no  → Relay's memory, if you said yes
  ```

- **Memory flows one way, with no plugin system.** WongStack stays the source of your memory. This repo gets it with each WongStack update, as today. At each plugin release, a script here copies memory into the Relay Everything plugin, and a check fails when the copy is old. WongStack needs one change for this: memory asks its store by name, and no longer writes database commands itself.
  ```text
  WongStack  (source)
     │  update, as today
     ▼
  Relay Everything repo  (internal)
     │  copy at each plugin release
     ▼
  Relay Everything plugin  (public, one install)
     │  your computer's key
     ▼
  Your space
  ```

**Not breaking:** memory is off until you say yes, so an existing install works as today.

## What the build needs

- **WongStack's memory change, live and synced here**: Needs you. Ship WongStack's [memory change](https://github.com/matthewwong525/WongStack/tree/modular-memory-plugin) (named requests and a settings file; no plugin system), then `/wong-sync` here.
- **Every other choice**: Ready. Asked in the chat.

## Capabilities

### New Capabilities

- `relay-memory-store`: each person's space answers WongStack memory's twelve operations, with Relay Everything's add-only history and its five kinds.

### Modified Capabilities

- `relay-agent-plugin`: setup asks whether to turn memory on; with it on, the plugin's copy of WongStack's memory runs, using Relay's topics and adding notes and chats to a topic pull; it stays off in a repo with its own memory.

## Impact

- **Server:** `app/worker/apps/relay/memory-store.ts` (new) answers the twelve operations through WongStack's `serve()`; the connector's `/v1/` routes and `key-rules.ts` change; migration `schema/space-migrations/0017_memory_store.sql`.
- **Plugin:** `plugin/memory/` (the copy, made by `scripts/copy-plugin-memory.mjs`), `plugin/memory-profile.mjs` (new), `plugin/test/memory-copy.test.mjs` (new), `plugin/bin/connect.mjs` (the setup choice), `plugin/bin/hook.mjs` and `plugin/hooks/hooks.json` (memory's hooks when on), `plugin/skills/` (memory's skill), README, version `0.5.0`.
- **Docs:** `wiki/stack/relay-knowledge-web.md`, `wiki/stack/relay-chats.md`, the site's API and plugin pages, `npm run relay:api-doc`.
- **Depends on** WongStack's memory change: named requests and a settings module (design §7).

## Decision log

- **2026-11-10** — Asked, at `/ship`, whether to wait for WongStack → chose to move the agents' database into its own change, `relay-agent-database`, and ship it now.
- **2026-11-10** — Asked how one install brings memory → chose that Relay's plugin needs `memory@wongstack`; superseded by the next two entries.
- **2026-11-10** — Asked, after the first draft, whether a plugin that depends on another is worth it → Matthew found it too complicated and chose to keep his own memory but ship it inside Relay Everything's plugin as a copy, with a setup choice to turn it on or keep only notes and chat saving.
- **2026-11-10** — Asked whether WongStack still needs memory as a plugin → first kept a plugins folder without the shop; superseded by the next entry.
- **2026-11-10** — Asked, after Matthew proposed WongStack → Relay Everything (internal) → Relay Everything (public) with an adapter at sync, which whole architecture to plan → chose that chain with no plugin architecture in WongStack: WongStack gets named requests and a settings file, this repo's script copies memory into the public plugin at release, and the server answers from the space. A corrected note went to WongStack's memory chat.
- **2026-11-10** — Asked where facts go in a repo that has its own memory → chose the repo's own memory; Relay's plugin still gives notes there, and a repo that wants its chats and topics in Relay builds its own link.
- **2026-11-10** — Asked which list of fact kinds the space uses → chose the memory plugin's five; older facts show as their nearest new kind.
- **2026-11-10** — Assumed: only a computer key (`agent` reach) reaches the memory store; API keys and the AI connector keep their present memory reads, and a phone key reaches it not, because the plugin runs only on computers.
- **2026-11-10** — Assumed: a chat's transcript is its saved Relay Everything chat; the store keeps no second copy, because one fact lives in one place and the plugin already sends each chat.
- **2026-11-10** — Assumed: memory's number ids are a new number column on each fact, beside the `f…` id, because WongStack's interface and commands use numbers, and changing them now would slow its build.
- **2026-11-10** — Assumed: with memory on, the copy's topic list and topic match replace Relay's own; with memory off, Relay's own run as today; in a repo with its own memory, neither runs, because two would show each topic twice, memory off must keep today's topics, and Matthew chose that a repo's own memory owns its topics.
- **2026-11-10** — Assumed: with saving off in a project, Relay's settings for memory give no store there, because saving off must keep that project's chats, and the facts from them, out of the space.
- **2026-11-10** — Assumed: memory is off until the person says yes at `/relay:connect`, and the answer is kept on the computer, because an existing install must not start saving facts unasked.
- **2026-11-10** — Assumed: the copy is made by a script at each plugin release from this repo's synced memory files, by a short list that leaves out WongStack's own database code, and a test fails when the copy differs from the source, because a hand copy goes stale.
- **2026-11-10** — Assumed: the copy finds Relay's settings through `WONG_MEMORY_PROFILE`, which Relay's hook and memory skill set, because that seam is already in WongStack's plan and needs nothing new there.
- **2026-11-10** — Assumed: a named-request seam in WongStack over an adapter that rewrites memory's database commands, because five of memory's client files write those commands today, and a rewrite would break at each memory change.
