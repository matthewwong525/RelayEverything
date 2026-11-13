# Update WongStack to 61.0.0: memory tidies itself with no command, search by words only, and every chat runs WongStack with no plugins

**Status:** shipped
**Branch:** sync-wongstack-updates
**Open questions:** none

## Why

This repo runs WongStack 55.2.1, and 61.0.0 is out. The daily memory tidy now does the whole job and shows what got better. Search is simpler and needs no setup. A chat that waits in the middle of your command goes on with it. Every chat runs memory, Daily and Access from the project's settings, with no plugin to turn on, also in a workspace Claude Code has not trusted. The Relay Everything plugin carries a copy of memory, so it gets the simpler search in a new plugin version.

## What Changes

- **What you get: a memory tidy that picks its own work and shows what got better.** The first chat of the day starts the tidy, as today. It now works on the weakest place first: new facts not yet read, facts with no topic, topics too big to read. The line at the start of a chat says which numbers changed. A tidy has 60 minutes and keeps the parts it finished.
  ```text
  Last tidy (2026-11-13 on wongos-16gb):
    facts with no topic   40 -> 12
    labels with no page    9 -> 3
    pages due a check      6 -> 2
  ```
- **What you get: search by words, chats that go on, and 1Password.** Memory search finds a page when your question shares words with it, with no setup on any computer. A chat that stops in the middle of a command you typed, such as a publish, goes on by itself when its wait ends. Any question a chat asks you comes on a card. The agent's browser adds 1Password, and signs in with a login from it only after your yes.
  ```text
  You type "publish it"     chat waits for another chat
            │                         │
            └──── wait ends ──────────┘
                      ▼
            chat goes on with the publish
            (a new risky step still asks you)
  ```
- **What changes in how you work.** One command changes: to pick up saved work, type `/apply` and the work's name, not the old pick-up command. `/schedule` stays and now loads in every chat, also in a workspace Claude Code has not trusted. The command for a manual memory tidy goes; ask *tidy memory now* instead.
  ```text
  Before                 After
  ------                 -----
  /continue <name>       /apply <name>
  /schedule              /schedule (every chat)
  /dream-memory          the daily tidy, or "tidy memory now"
  ```
- **What of yours stays.** Every fact, schedule, note and setting stays. Relay Everything's app, server, website and phone app work as today. The public plugin list still shows only the Relay Everything plugin. Your local lines are kept: the phone app pictures in the plan tools, the script tip for review cards, the brand page link, the *ship every chat* link, and your own stack pages.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, server, site, phone app
  Public plugin list: Relay Everything only
  Schedules: "Keep my chats in line" (the old
    "Wiki tidy" already ended)
  Your edits in 6 files (merged, not overwritten)
  ```
- **What changes for people with the plugin.** The Relay Everything plugin goes to version 0.6.1 with the new memory copy: simpler search, and a short local count of each memory look-up that never leaves the computer. Its website page and guide say so in one sentence.
  ```text
  Relay Everything plugin 0.6.0 → 0.6.1
    memory search: words only, no setup
    look-up counts: on the computer, 30 days, never sent
  ```
- **What is left out, and why.** No schedule move is needed: no old schedule file or older Cloudflare runner exists here, and no schedule runs the old tidy command. The plugin still leaves out the daily tidy, because the plugin has its own daily build.
  ```text
  Checked, nothing to do:
    old schedule files ......... none
    older Cloudflare runner .... none
    schedule running old tidy .. none
    meaning-search folder ...... none on this computer
  ```
- **What you do yourself.** Nothing. After the publish, the build takes WongStack's old memory and Daily plugins out of Codex on this computer, so their checks run once. If the browser asks, sign in to 1Password once and set it to lock after 8 hours; if you don't want it, ask the agent to *remove my password manager*. After the publish, the build republishes the website and the server.
  ```text
  You:        say yes
  The build:  copy, merge, check, publish
  After:      republish website and server
  Optional:   sign in to 1Password once
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.0.0 at commit `9d63c758` on this computer.
- **Your saved schedules, to check for the old tidy command**: Ready. Read from the app on 2026-11-12: two schedules, neither runs it.
- **Codex on this computer**: Ready. It has `memory@wongstack` and `daily@wongstack` from WongStack's own list; the build removes them after the publish and adds nothing (Decision log).

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools and the plugin's copy of memory, and no requirement in `openspec/specs/` (checked: `relay-agent-plugin`, `relay-chats`, `relay-memory-store`). The change sets `skip_specs: true`.

## Impact

- Settings: `.claude/settings.json` and `.codex/hooks.json` take 61.0.0's whole, one copy of each module hook; the `enabledPlugins` lines go, and the five module plugin manifests go.
- 223 of 827 WongStack parts changed (preflight `status: update`, `catchUp.needed: false`, `updatingComplete: true`): 143 to copy, 5 already current, 46 to remove, and 29 marked as locally edited (23 changed, 6 removed). Groups and the merge list are in the design.
- Agent folder: the browser and Daily each become one folder, with hand-over and shop under `.claude/skills/browser/skills/` and schedule under `.claude/skills/daily/skills/`; the old `.claude/skills/{continue,schedule,hand-over,shop}/` and memory's nested `dream-memory` go.
- Plugin: `plugin/memory/` remade by `scripts/copy-plugin-memory.mjs`; `plugin/.claude-plugin/plugin.json` to 0.6.1; one sentence in `plugin/README.md` and `site/src/content/docs/connections/claude-code.md`.
- Files outside the payload that name a moved part: `wiki/development/README.md`, `app/package.json`, `.env.example`.
- App: only `app/worker/apps/inbox/schedule-store.ts` changes (copy). No route, `relay_*` table or memory database migration, so no `relay:api-doc` run and no `memory.mjs migrate`.

## Decision log

- **2026-11-12** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement names memory search modes or look-up counts.
- **2026-11-12** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-12** — Assumed: no other work overlaps, because the other workspace (`/root/relay-ring` on main) has no change, and the open plans change the phone app or Google connections.
- **2026-11-12** — Assumed: 58.0.0's hand steps need nothing here, because `/root/relay-ring/.env` has no older runner key, no `schedules/` folder or Daily routine file exists, and `~/.local/share/wongstack/documents` is absent.
- **2026-11-12** — Assumed: 59.0.0's hand step needs nothing, because the app lists two schedules, *Keep my chats in line* (on) and *Wiki tidy* (ended), and neither runs `/dream-memory`.
- **2026-11-12** — Assumed: the plugin goes to 0.6.1, not 0.7.0, because its commands and settings stay the same and only memory search and a local count change.
- **2026-11-12** — Assumed: the plugin's website page and guide get one sentence about the local look-up count, because it keeps the words of a question that found nothing in a file on the person's computer, and the page already says what stays on the computer.
- **2026-11-12** — Assumed: drop the old-runner lines from `.env.example`, because their guide page goes and this install never had that runner.
- **2026-11-12** — Assumed: the `.claude/settings.json` hook lines and `enabledPlugins` stay as they are, because the memory, Daily and Access hook files are the same in 59.0.0, and the browser's new plugin folder has no hooks.
- **2026-11-12** — Assumed: 22 of the 29 parts marked as locally edited take upstream whole (16 changed, 6 removed), because each matches the 55.2.1 copy as `install-path.mjs` writes it; `.claude/skills/daily/scripts/worker.mjs` takes upstream too, because its local lines are the *retired server answer* fix that 57.1.1 shipped. Six files keep local lines (design §Merge list).
- **2026-11-12** — Assumed, inside `/ship`: the phone app link in `.claude/skills/plan/SKILL.md` stays in that file, at the end of 59.0.0's *A card shows the closest real result* sentence, and does not move into `references/prototypes.md`, because the plan skill is read on every plan and this keeps one locally edited file, not two. `merge-check.mjs` names only this kept line (`SKILL.md` line 31).
- **2026-11-12** — Assumed, inside `/ship`: the *Open its page in a browser before you build* tip stays under the `live` fence bullet of `.claude/skills/plan/references/drawings.md`; the other four local lines go back where they were.
- **2026-11-12** — Check: `.agents/skills/schedule/scripts/tidy.test.mjs` is not deleted: this repo's own test moves with the schedule command to `.agents/skills/daily/skills/schedule/scripts/tidy.test.mjs`, and `app/package.json` runs it at the new path. No test is taken out and no check setting changes.
- **2026-11-12** — Check: `app/package.json` changes only the path of the schedule tidy test in `npm test`, to `../.agents/skills/daily/skills/schedule/scripts/tidy.test.mjs`; every check stays.
- **2026-11-12** — Assumed, inside `/ship`: `.env.example` also drops `WONG_ROUTINE_GITHUB_TOKEN`, the third line of the same *Legacy cloud scheduling* block, because the page it names goes and `/root/relay-ring/.env` has no `WONG_ROUTINE*` line.
- **2026-11-12** — Assumed, inside `/ship`: `scripts/copy-plugin-memory.mjs` also treats a link to memory's `README.md` (which the copy leaves out) or to WongStack's pages on GitHub as a link out of the plugin, and keeps only its words, because 59.0.0's memory `SKILL.md` links there and the copy test needs each kept link to land in the plugin.
- **2026-11-12** — Assumed, inside `/ship`: `codex-plugin.mjs` does not run here, because in this checkout it adds Relay Everything's plugin list to Codex and installs the Relay Everything plugin for every folder, and Matthew keeps that plugin out of Codex until saving can stay off for Claymoo folders. Codex keeps `memory@wongstack` and `daily@wongstack` from WongStack's own list, as 55.2.1 set them.
- **2026-11-12** — Note for upstream: 59.0.0's `wiki/wiki-style.md` still links [`/dream-memory`](../../../wiki/development/wiki-dream.md), which 59.0.0 removes. It stays as upstream ships it.
- **2026-11-12** — Built inside `/ship`: preflight 223 units at `facaf5f9`; 159 files copied and 5 already current, all equal to `install-path.mjs` output; the `WONG-STACK` block copied into `AGENTS.md`; 52 removed (as plain file removals, which the save stages) with their empty folders; 6 files merged; plugin memory copied again (39 files) at 0.6.1. Merge check names only the kept plan line; preflight `current`; local checks pass (one webhook test timed out under a computer load of 23 and passed on the rerun; this change touches no webhook code); a fresh chat printed the memory digest; `schedule.mjs list` lists *Keep my chats in line* (on) and *Wiki tidy* (ended); the review page builds with no warning.
- **2026-11-12** — Asked how to handle the schedule command, which 59.0.0 nests inside Daily's plugin folder, where it does not load in untrusted chat workspaces → Matthew asked to unpack it at sync. Asked where → chose WongStack first: the WongStack workspace *Sync unpacks nested commands* teaches `/wong-sync` to unpack nested commands (schedule, hand-over, shop) into top-level skill folders; this change waits for it, syncs again, then ships.
- **2026-11-12** — Assumed, inside `/ship` after the second look: the plugin's chat-start preload (`plugin/lib/daily-off.mjs`) trims look-up counts to 30 days, because the copy trims them only in the daily tidy, which the plugin turns off, so the 30-day sentence would be false; the sentence also says *a question that got no good answer*, the copy's real rule.
- **2026-11-12** — Assumed, inside `/ship`: task 5.1 no longer runs WongStack's Codex helper, matching the build's Decision log line.
- **2026-11-12** — Built inside `/ship`: WongStack 60.0.0 (*Sync unpacks nested commands*, commit `c7450cee`) published, so this change took its 37 parts: `schedule`, `hand-over`, `shop` and `services` are top-level skill folders again, the `WONG-STACK` block says `/schedule`, and `wiki/development/daily.md` keeps its *ship every chat* line. Merge check clean, preflight `current`, local checks pass.
- **2026-11-13** — Asked whether to publish 60.0.0 now or wait for the WongStack change *Every chat runs WongStack's hooks, with no plugins* (being built, no pull request) → chose to wait and take both in this update, so the settings and Codex files change once.
- **2026-11-13** — Built inside `/ship`: WongStack 61.0.0 (*Every chat runs WongStack's hooks, with no plugins*, commit `9d63c758`) published, so this change took its 46 parts: 32 copied, the 10 module plugin manifests removed, `.claude/settings.json` and `.codex/hooks.json` taken whole (each local hook was already in upstream's, so each runs once, and `enabledPlugins` goes), and `wiki/development/daily.md` keeps its *ship every chat* line. `scripts/copy-plugin-memory.mjs` drops the two gone plugin folders from `LEFT_OUT`. Merge check clean, preflight `current`, local checks pass, the memory start prints its digest, and `/schedule list` lists both schedules.
- **2026-11-13** — Assumed, inside `/ship`: keep `.claude-plugin/marketplace.json`, which the preflight's catch-up still names, because it is Relay Everything's public plugin list, not WongStack's, and lists no module. Note for upstream: the catch-up could name only a list that holds a module plugin.
- **2026-11-13** — Assumed, inside `/ship`: run `codex-plugin.mjs` once, after the merge, not now. It removes only `memory@wongstack` and `daily@wongstack` (WongStack's list is at `/root/WongStack`, not this checkout, so no list goes), and adds nothing. Before the merge, `/root/relay-ring` on 55.2.1 still gets its Codex memory from those plugins; after it, main has the project hooks, and ClaymooApp (51.10.0) already runs its own.
- **2026-11-13** — Archived inside `/ship` at `openspec/changes/archive/2026-11-13-wongstack-59-update`, branch `sync-wongstack-updates`.
