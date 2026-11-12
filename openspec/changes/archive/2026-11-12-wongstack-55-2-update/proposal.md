# Update WongStack to 55.2.1: the new memory, with a daily tidy and the files behind each fact

**Status:** ready-to-ship
**Branch:** sync-wongstack-memory-system
**Open questions:** none

## Why

This repo runs WongStack 51.10.0, and 55.2.1 is out. The big part is the new memory. It tidies itself once a day, links topics that connect, and shows the files behind each fact. Memory is now one self-contained folder, so the Relay Everything plugin can carry a copy of it later. That plugin work is planned in its own chat, and it is built after this update.

## What Changes

- **What you get: memory that tidies itself each day.** Your first chat of the day starts a short tidy in the background, and the chat never waits for it. The tidy saves what your chats learned and merges facts that say the same thing. It also puts lasting facts on their topic's page, links topics that connect, and checks a few old pages. The *Wiki tidy* schedule ends, because the daily tidy does its work. You can ask any chat *when did memory last tidy?*, *stop the daily memory tidy* or *tidy memory now*.
  ```text
  First chat of the day
    └─ tidy starts in the background (≤ 30 min)
         1. save what chats learned
         2. merge facts that say the same thing
         3. put lasting facts on their topic page
         4. link topics that connect
         5. check 3 old pages and 1 spec
  Chat start shows:
    Last tidy (2026-11-13): added 4, pages 2
  ```
- **What you get: memory answers that point at the right files.** An answer ends with up to eight files that its facts are about. Each file shows the facts that led to it, so the assistant opens the right place first. One look at a topic, a file, a past change or a fact number also shows what it connects to: the page, related topics, open questions and decisions.
  ```text
  recall "voice notes off screen"
    Facts …
    Passages …
    Files behind these facts (a place to start):
      a voice-notes file      ← #685, #354
      phone-pictures.md       ← #657
  ```
- **What you get: memory, the build loop, Daily, the browser and Access as five self-contained modules.** Each one is a folder with its own hooks and one settings file for this repo. This is what lets the Relay Everything plugin carry its own copy of memory with no second plugin. Several chats can share one live view, a tab for each chat. A chat's click goes on behind your turn in the browser and does not stop it.
  ```text
  WongStack 55.2.1
    memory ─► this repo ─► later: Relay plugin copy
    loop     (/explore /plan /apply /save /ship …)
    Daily    (check-ins, /schedule)
    browser  (browser, live view, shop)
    Access   (who signs in, services)
  ```
- **What changes in how you work.** Very little. The commands are the same. Chats no longer save facts at */save* and */close*: memory saves each chat by itself when it ends. A reminder is now *remind me* in any chat, which makes a one-time schedule. The *tell* and *watch* asks are gone. The Inbox opens on the plans that wait for you.
  ```text
  Before                  After
  ------                  -----
  /save, /close save      each chat saves itself
  "Wiki tidy" schedule    daily tidy
  remind / tell / watch   "remind me" → one-time
  Inbox: your chats       Inbox: plans waiting
  ```
  The app deletes the Inbox's saved list of your chats when it deploys. This can't be undone.
- **What of yours stays.** Every fact, schedule, OK and setting stays. Relay Everything's app, website, phone app and plugin work as today. The public plugin list still shows only the Relay Everything plugin. Your local edits to the plan tools, the screen rules, the app's own server files and the home proxy setting are kept.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, site, phone app, plugin
  Public plugin list: Relay Everything only
  Your edits in 27 files (merged, not overwritten)
  ```
- **What is left out, and why.** The Relay Everything plugin does not get memory in this change. That is its own plan, opened in its own chat, because it also needs a memory store in your space and a setup choice. WongStack's memory, Daily and Access are not added to the public plugin list, because people who install Relay Everything do not need WongStack's internal tools. WongStack's own tests and sample plans stay in WongStack.
  ```text
  This change:   WongStack 55.2.1 in this repo
  Next change:   memory in the plugin (own chat)
  Not added:     WongStack tools in the public list
  ```
- **What you do yourself.** Nothing, unless you use Codex on another computer: its next chat there names one command to run. After the publish, the build updates the memory database once and adds Daily to Codex on this computer.
  ```text
  You:        say yes
  The build:  copy, merge, check, publish
  After:      update the memory database once
              add Daily to Codex on this computer
  ```

## What the build needs

- **The WongStack source**: Ready, version 55.2.1 at commit `a282a4a9` on this computer.
- **Admin sign-in to the memory store, for the one database update after the publish**: Ready. It runs from this computer as Matthew.
- **Codex on this computer**: Ready. Memory is already added from WongStack's own list.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools, not a Relay Everything behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 635 of 938 WongStack parts changed (preflight `status: update`, `catchUp.needed: false`): 186 modified and 268 added with no local edits (copy), 153 removed with no local edits (delete), 27 with local edits (merge), 1 removed and already missing. Groups and the merge list are in the design.
- Agent folder: five modules arrive as real skill folders (`.claude/skills/{memory,loop,daily,schedule,browser,hand-over,shop,access}/`); repo profiles at `.claude/{memory,loop,daily,browser,access,inbox}/`; `dream-memory` and `services` skill folders go away (now `/memory:dream-memory` and `access/skills/services`); `reply-link` is added.
- App: memory route `/_memory/v2/`, Access module slots (`app/worker/access-slots.ts`), Inbox chat list removed, MCP forwarding removed (no tool here uses it). Five Relay files that import `app/worker/access.ts` move to the new module.
- Memory store: one D1 migration, applied by an admin `memory.mjs migrate` after the server deploy.
- Codex: `.agents/hooks.json` loses the module-install check, because the root plugin list is Relay Everything's public one.
- No Relay Everything route, `relay_*` table, website page or plugin file changes, so no `relay:api-doc` run.

## Decision log

- **2026-11-12** — Asked how to split *update WongStack, and bring its new memory into Relay Everything and the plugin* → chose the update here and the plugin memory in a new workspace, *Relay Everything plugin gets WongStack memory*, on the saved `relay-memory-plugin` plan; it builds after this publishes.
- **2026-11-12** — Asked whether to open that workspace on the saved plan's branch (one plan-only commit by Matthew) → chose to open it.
- **2026-11-12** — Assumed: a request from the WongOS chat (WongOS keeps its memory in Matthew's Relay Everything space) goes to the plugin workspace's brief, not here, because it is about the memory store in a person's space, which that plan owns.
- **2026-11-12** — Assumed: keep the root plugin list (`.claude-plugin/marketplace.json`) as Relay Everything's public list and not add WongStack's memory, Daily and Access to it, because anyone who adds the public list would see internal tools that work only in this repo, and Matthew chose no second plugin beside Relay Everything's (#628).
- **2026-11-12** — Assumed: drop the Codex start check that installs every plugin in the root list from `.agents/hooks.json`, and add Daily to Codex on this computer from WongStack's own list (`daily@wongstack`, beside the `memory@wongstack` that is there), because with Relay Everything's list that check would ask each Codex chat to install the Relay Everything plugin instead.
- **2026-11-12** — Assumed: drop the local *When your turn holds the browser* keyboard route from the old browsing guide, and point Matthew's person page at the new *your turn keeps its tab in front*, because 53.2.0 makes another chat's click go on behind his turn.
- **2026-11-12** — Assumed: move the local line *keep the proxy setting on, on Matthew's computers* from the old proxy guide to Matthew's person page, because it is about one person, and a line in the browser module's folder would make each later update merge it again.
- **2026-11-12** — Assumed: keep the *Relay devices* policy test case from the removed login-management test, in the test that now owns that check in the Access module's server folder, because it guards Relay Everything's phone token policy.
- **2026-11-12** — Assumed: no spec delta (`skip_specs: true`) and no website page change, because no Relay Everything behavior changes.
- **2026-11-12** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-12** — Assumed: no other work overlaps, because the only other busy workspace plans a device check step, and the open plans change the phone app.
- **2026-11-12** — Assumed: post-publish steps (republish the site and server, the memory database update, Daily in Codex) run after the merge as the design's Migration Plan says, not as tasks, because `/ship` archives only a change with every task ticked.
- **2026-11-12** — Assumed: the merge check names four kept local lines, and each stays: `.claude/hooks.json` leaves out the `codex-plugin.mjs --check` start hook (above); `.claude/skills/plan/SKILL.md` keeps the phone app link to [real pictures of a phone app screen](../../../wiki/development/phone-pictures.md) beside upstream's new screen test words; `app/package.json`'s `npm test` keeps the Relay Everything checks after upstream's new service-records check path (`../.agents/skills/access/scripts/check-definitions.mjs`, the same file as `.claude/` through the folder link); `paseo.json` keeps `worktree.setup` as a list, with upstream's new `.claude/loop/worktree-secrets.mjs` path.
- **2026-11-12** — Assumed: the *Relay devices* policy case goes into `app/worker/employee-access/sign-in-list.test.ts`, the test that now holds the login policy cases of the removed `login-management.test.ts`.
- **2026-11-12** — Check: `app/worker/relay-only.ts` and `app/tests/relay.ts` call Relay Everything's routes as an open install (`WORKSPACE_LOGIN` off, no Access address and no owner email), because 55.x's Access module refuses a call with no person unless the install is open, and a Relay Everything call by a device key or the page's own sign-in has no Access person; each route still opens only its caller's space. No test is skipped.
- **2026-11-12** — Check: `.github/scripts/wiki-links.mjs` changes only its import, to the memory module's new `.agents/memory/lib/links.mjs`; `.github/workflows/deploy.yml` changes only a comment, to `.claude/loop/staging/live-look.sh`.
- **2026-11-12** — Check: `app/.oxlintrc.json` lets `src/apps/access/App.tsx` import the Access module's page (`.agents/skills/access/screen/main.mjs`), because 55.x serves that page from the module; every other mini app keeps its import bounds.
- **2026-11-12** — Check: `app/knip.jsonc` drops the `worker/access.ts` entry with the file, and ignores `src/lib/utils.ts`, the ready-made parts' helper, as upstream does; `app/package.json` moves the service-records check to `.agents/skills/access/scripts/check-definitions.mjs` and takes no check out.
- **2026-11-12** — Check: `app/vitest.config.ts` lets the test server read `..` so the Access module's own `*.test.mjs` tests run too; it adds tests and takes none out.
- **2026-11-12** — Check: `app/tsconfig.worker.json` and `app/worker/checked-caller.test.ts` lose the hand-asserted Access pass check with `tests/employee-access/unchecked-caller.ts`, because 55.x removes the `Core` pass it guarded; the Access module's gate is tested in `.agents/skills/access/server/index.test.mjs`.
- **2026-11-12** — Check: `app/src/apps/access/Leaving.test.tsx`, `app/src/apps/access/levels.test.ts`, `app/src/apps/access/note.test.ts`, `app/src/apps/access/Notices.test.tsx`, `app/src/apps/access/PersonPage.test.tsx`, `app/src/apps/access/ProjectStep.test.tsx`, `app/src/apps/access/Pushers.test.tsx`, `app/src/apps/access/Roles.test.tsx`, `app/src/apps/access/Services.test.tsx`, `app/src/apps/access/status.test.ts`, `app/src/apps/access/style.test.ts`, `app/src/apps/access/subjects.test.ts`, `app/src/apps/access/Welcome.test.tsx` and `app/src/lib/seal.test.ts` are deleted with the React Access page and `seal.ts`, because 55.x serves the page from the Access module; its `.agents/skills/access/screen/*.test.mjs` tests cover the same parts.
- **2026-11-12** — Check: `app/src/apps/inbox/Chats.test.tsx` and `app/worker/apps/inbox/chats.test.ts` are deleted with the Inbox chat list, which 55.x removes.
- **2026-11-12** — Check: `app/worker/api/mcp.test.ts`, `app/worker/api/forward-mcp.test.ts` and `app/worker/api/services.test.ts` are deleted with MCP forwarding and the old services route, because 55.x removes MCP forwarding (no tool here uses it) and serves `/api/services` from the Access module, tested in `.agents/skills/access/server/services.test.mjs`.
- **2026-11-12** — Check: `app/worker/employee-access/core.test.ts`, `app/worker/employee-access/key-levels.test.ts`, `app/worker/employee-access/keys-route.test.ts`, `app/worker/employee-access/tools-route.test.ts` and `app/worker/employee-access/login-management.test.ts` are deleted with the code that moved into the Access module, tested in `.agents/skills/access/server/*.test.mjs`, `app/worker/access-slots.test.ts` and `app/worker/employee-access/sign-in-list.test.ts`; the *Relay devices* case moves to `sign-in-list.test.ts`.
- **2026-11-12** — Assumed: `.agents/skills/access/server/services.test.mjs` builds its made-up `sk-` key from two parts at run time, because `scripts/public-check.mjs --tree` refuses text shaped like a key, and the rule is to take the detail out, never to weaken the check. The test checks the same thing. The next WongStack sync merges this line; it is worth sending upstream.
- **2026-11-12** — Assumed: Claude Code skipped the memory, Daily and Access modules' own hooks in a fresh chat here, because it loads a `.claude/skills/<module>/` plugin only in a folder you trusted, and these workspaces are not. So `.claude/settings.json` runs the three modules' hooks itself, by the design's fallback, at `$CLAUDE_PROJECT_DIR/.claude/skills/<module>/`. In a trusted checkout the plugin and these lines both run; the next sync keeps these lines as a local edit.
- **2026-11-12** — Assumed, inside `/ship`: task 3.3 checks only that the memory start hook runs before the deploy, and the digest and *files behind these facts* check moves to the Migration Plan, because production serves the new memory route only after the merge's deploy, and `/ship` archives only a change with every task ticked.
- **2026-11-12** — Asked, after the second look found that a trusted checkout would run the memory, Daily and Access hooks twice (the plugin from its skill folder and the settings lines), how to fix it → chose one copy always: `.agents/settings.json` keeps the hook lines and sets `enabledPlugins` `memory@skills-dir`, `daily@skills-dir` and `access@skills-dir` to false, a local edit each sync keeps; Matthew may also trust `/root/relay-ring` on his own.
- **2026-11-12** — Built inside `/ship`: 453 files copied, 153 removed, 27 merged, install record at 55.2.1. Merge check names only kept local lines, preflight `current`, local checks pass, second look clean after the hooks fix (`claude plugin list` in the trusted WongStack checkout names `memory@skills-dir`, `daily@skills-dir`, `access@skills-dir`). Main's red public-beta run passed on its rerun, on Matthew's yes. Saving for task 4.2.
- **2026-11-12** — Task 4.2 passed: PR #121 checks SUCCESS at 1eaf427.
- **2026-11-12** — Archived inside `/ship`: main's public-beta run for #120 failed twice at Apple's beta review and passed on its third run, after a 20-minute wait; this change touches no phone code.
