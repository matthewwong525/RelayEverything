# Your WongStack memory inside the Relay Everything plugin, saved in your space

**Status:** planned
**Branch:** relay-memory-plugin-plan
**Open questions:** none

## Why

Matthew likes his own WongStack memory and wants it in Relay Everything, but a plugin that needs a second plugin from a second shop is too complicated. Relay Everything's plugin can carry a copy of that memory, turned on by one setup choice, and save it in each person's space. WongOS will also keep all its memory in Matthew's space, so Relay Everything is tested on real, daily use.

## What Changes

- **One setup choice: memory or not.** When you connect a computer, Relay Everything asks *Also remember things for you?* Say no, and the plugin does what it does today: notes, health, places, *around a moment*, chat saving, and the daily build of your knowledge web. Say yes, and it also runs your WongStack memory. Nothing else to install, in Claude Code or Codex.
  ```text
  /relay:connect
    Open the link and sign in… connected.
    Also remember things for you?
      Yes → memory saves facts in your space
      No  → notes, health, places, chats only
  ```

- **Your memory, saved in your space.** With memory on, in a repo with no memory of its own, the chat-start summary, topic lines, search, pulls and before-edit warnings work as in WongStack, and the facts go to your Relay Everything space. Facts are only added, never edited: a new fact replaces an old one, and the old one stays readable.
  ```mermaid
  sequenceDiagram
    participant M as Memory (in the plugin)
    participant R as Your Relay space
    M->>R: save "battery is 50 mAh"
    R->>R: add it, mark 40 mAh replaced
    M->>R: search "battery"
    R-->>M: 50 mAh (40 mAh kept as history)
  ```

- **One daily job, not two.** Relay Everything's daily build stays the one daily job: it tidies your topics and pages. Memory saves what each chat learned when the chat ends, and the build no longer reads a chat that memory already read.

- **WongOS keeps its memory in your space.** A WongStack project, such as WongOS, can point its own memory at your space with this computer's key. It gets every memory request answered there, with its own chat transcripts kept beside its facts.
  ```text
  WongOS's memory ──┐
                    ├─key─► Your space
  Plugin's memory ──┘       (one memory table)
  ```

- **Move WongOS's memory once.** A one-time import copies WongOS's facts into your space, and a second run right after WongOS switches adds what came in between. It keeps each fact's number, date, author, kind, topics, sources and replaced-by link, plus each chat's transcript. WongOS's old memory stays as a read-only backup. WongOS's own plan, *Relay Everything in WongOS*, runs the import and switches WongOS over.
  ```text
  WongOS store (2,067 facts, 469 chats)
     │  import: read through memory's own requests
     ▼
  Your space   #628 stays #628
  ```

- **One list of fact kinds.** New facts use WongStack memory's five kinds. Older facts keep their words, and each shows as its nearest new kind. The daily build writes the five kinds from now on.
  ```text
  Old kind               Shows as
  open                   thread
  preference             feedback
  fact, decision, plan   project
  reference              reference
  ```

- **Relay Everything keeps your life data.** Notes, health, places, and *around a moment* stay Relay Everything's own; memory never reads them. Memory gets your topics from Relay Everything, so a chat starts with them and a message that names one brings it in. When you pull a topic, Relay Everything adds its notes and chats to memory's answer.

- **Memory runs once in a chat.** In a WongStack project, the project's own memory runs and the plugin's copy stays off, wherever the project keeps its facts. Notes, health, places and chat saving still work there.
  ```text
  Repo has memory?
    yes → the repo's memory only (WongOS: saved in your space)
    no  → the plugin's memory, if you said yes
  ```

- **Memory flows one way, with no plugin system.** WongStack stays the source of your memory. This repo gets it with each WongStack update, as today. At each plugin release, a script here copies memory into the Relay Everything plugin, and a check fails when the copy is old.
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

- **WongStack 55.2.1, synced here**: Needs you. Publish the chat *Update to WongStack 55.2.1* ([WongStack 55.2.1](https://github.com/matthewwong525/WongStack/releases/tag/v55.2.1)), which brings it in. This build starts after that update is live; whichever is published second catches up.
- **WongOS's switch**: Ready. This build does not wait for it. The plan *Relay Everything in WongOS* builds on this store; it updates WongOS to WongStack 55.2.1, runs the import, and keeps the old store read-only.
- **Every other choice**: Ready. Asked in the chat.

## Capabilities

### New Capabilities

- `relay-memory-store`: each person's space answers WongStack memory's twelve requests for the plugin's copy and for a full WongStack project, keeps transcripts, imports a WongStack memory once, and keeps Relay Everything's add-only history and the five kinds.

### Modified Capabilities

- `relay-agent-plugin`: setup asks whether to turn memory on; with it on, the plugin's copy of WongStack's memory runs, using Relay's topics and adding notes and chats to a topic pull; it stays off in a repo with its own memory; the daily build skips chats memory read.

## Impact

- **Server:** `app/worker/apps/relay/memory-store.ts` (new) answers the twelve requests through WongStack's `serve()`; `memory-import.ts` (new) for the one-time import; the connector's `/v1/` routes, `key-rules.ts`, and `GET /v1/chats` (a chat memory read); migration `schema/space-migrations/0019_memory_store.sql`; transcripts in the person's held files.
- **Script:** `scripts/import-wongstack-memory.mjs` (new).
- **Plugin:** `plugin/memory/` (the copy, made by `scripts/copy-plugin-memory.mjs`), `plugin/memory-profile.mjs` (new), `plugin/test/memory-copy.test.mjs` (new), `plugin/bin/connect.mjs` (the setup choice), `plugin/bin/hook.mjs` and `plugin/hooks/hooks.json` (memory's hooks when on), `plugin/bin/build.mjs` and `plugin/build/` (five kinds, skip read chats), `plugin/skills/` (memory's skill), README, version `0.6.0`.
- **Docs:** `wiki/stack/relay-knowledge-web.md`, `wiki/stack/relay-chats.md`, the site's API and plugin pages, `npm run relay:api-doc`.
- **Depends on** WongStack 55.2.1 synced here (design §7).

## Decision log

- **2026-11-10** — Asked, at `/ship`, whether to wait for WongStack → chose to move the agents' database into its own change, `relay-agent-database`, and ship it now.
- **2026-11-10** — Asked how one install brings memory → chose that Relay's plugin needs `memory@wongstack`; superseded by the next two entries.
- **2026-11-10** — Asked, after the first draft, whether a plugin that depends on another is worth it → Matthew found it too complicated and chose to keep his own memory but ship it inside Relay Everything's plugin as a copy, with a setup choice to turn it on or keep only notes and chat saving.
- **2026-11-10** — Asked whether WongStack still needs memory as a plugin → first kept a plugins folder without the shop; superseded by the next entry.
- **2026-11-10** — Asked, after Matthew proposed WongStack → Relay Everything (internal) → Relay Everything (public) with an adapter at sync, which whole architecture to plan → chose that chain with no plugin architecture in WongStack: WongStack gets named requests and a settings file, this repo's script copies memory into the public plugin at release, and the server answers from the space. A corrected note went to WongStack's memory chat.
- **2026-11-10** — Asked where facts go in a repo that has its own memory → chose the repo's own memory; Relay's plugin still gives notes there, and a repo that wants its chats and topics in Relay builds its own link. Still true for the plugin's copy; WongOS's own link is the 2026-11-12 entry below.
- **2026-11-10** — Asked which list of fact kinds the space uses → chose the memory plugin's five; older facts show as their nearest new kind.
- **2026-11-10** — Assumed: only a computer key (`agent` reach) reaches the memory store; API keys and the AI connector keep their present memory reads, and a phone key reaches it not, because the plugin runs only on computers.
- **2026-11-10** — Assumed: a chat's transcript is its saved Relay Everything chat; the store keeps no second copy. Superseded on 2026-11-12 by the entry that keeps transcripts.
- **2026-11-10** — Assumed: memory's number ids are a new number column on each fact, beside the `f…` id, because WongStack's interface and commands use numbers, and changing them now would slow its build.
- **2026-11-10** — Assumed: with memory on, the copy's topic list and topic match replace Relay's own; with memory off, Relay's own run as today; in a repo with its own memory, neither runs, because two would show each topic twice, memory off must keep today's topics, and Matthew chose that a repo's own memory owns its topics.
- **2026-11-10** — Assumed: with saving off in a project, Relay's settings for memory give no store there, because saving off must keep that project's chats, and the facts from them, out of the space.
- **2026-11-10** — Assumed: memory is off until the person says yes at `/relay:connect`, and the answer is kept on the computer, because an existing install must not start saving facts unasked.
- **2026-11-10** — Assumed: the copy is made by a script at each plugin release from this repo's synced memory files, by a short list, and a test fails when the copy differs from the source, because a hand copy goes stale.
- **2026-11-10** — Assumed: the copy finds Relay's settings through `WONG_MEMORY_PROFILE`, which Relay's hook and memory skill set, because that seam is already in WongStack's plan and needs nothing new there.
- **2026-11-10** — Assumed: a named-request seam in WongStack over an adapter that rewrites memory's database commands, because five of memory's client files write those commands today, and a rewrite would break at each memory change.
- **2026-11-12** — Matthew split the work: the WongStack 55.2.1 update in its own chat, the plugin memory here; this build starts after that update is live. His 2026-11-10 chain stands: WongStack → this repo by `/wong-sync` → a copy in the public plugin at release.
- **2026-11-12** — Matthew chose, in the chat *WongOS memory in Relay Everything*, that WongOS keeps all its memory in his Relay Everything space, to test it on real use. This replaces, for WongOS only, "a repo with its own memory keeps it" and the 2026-11-05 fact that WongStack keeps its own memory off Relay. So the store must serve a full WongStack project, import WongOS's facts once, and give their transcripts; the old store stays a read-only backup. WongOS's side is planned in *Relay Everything in WongOS*.
- **2026-11-12** — Checked WongStack 55.2.1 against this plan (design §7): every needed part shipped. Fitted §3 to the shipped shapes (digest, daily runs, `newTags`, `createdAt`, private sessions, transcripts), the route prefix to `/v1/memory/v2/`, and the copy to the self-contained plugin folder.
- **2026-11-12** — Assumed: the store keeps the transcripts memory sends, in the person's held files, and gives the saved chat only when no transcript was kept, because WongStack 52.0.0 makes memory send each chat's transcript itself, a WongStack project sends one with no Relay chat, and imported facts need theirs.
- **2026-11-12** — Assumed: the store follows WongStack's full role table, with each fact's author, owner and sharing kept, because the store check tests it, and WongOS's 31 team facts must keep their owner. Every key today is its own person's, so the person sees all of their space.
- **2026-11-12** — Assumed: a fact keeps memory's own sources as written, beside Relay's `relay:` sources, because the store check reads back exactly what was written, and the page and connector need a `relay:` link.
- **2026-11-12** — Assumed: the import keeps each WongOS fact's number, and moves the space's own facts above them in its first run, only while no memory has used the space, because WongOS's plans and pages cite facts by number, such as #628.
- **2026-11-12** — Assumed: with memory on, Relay's daily build stays the one daily job and the copy's own daily tidy stays off, because memory's tidy edits the repo's pages, which a side project does not want, and two daily jobs would tidy one web twice.
- **2026-11-12** — Assumed: the daily build skips a chat that memory already read, because both would save the same facts from it.
- **2026-11-12** — WongOS's plan (*Relay Everything in WongOS*) asked that the import run twice, before and right after its switch, read the old store through a profile it gives while that store refuses writes, and count by kind → the import keys each fact by its old number, adds only new facts on a later run, reads only, and answers counts by kind; the build's `check-facts` drops a fact the space already holds.
- **2026-11-12** — Assumed: plugin version `0.6.0`, because `0.5.1` shipped meanwhile and memory is a new feature.
