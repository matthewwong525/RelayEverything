# Update WongStack to 61.5.0: relay-ring gets its own background helper, so its line-up runs start again

**Status:** ready-to-ship
**Branch:** neat-donkey
**Open questions:** none

## Why

On this computer, one shared background helper starts every project's schedules. It runs ClaymooApp's copy, and that copy can't see relay-ring's sign-in. So each *Keep my chats in line* run for relay-ring stops with *Needs your OK*, and nothing happens. WongStack 61.5.0 gives each project its own helper, which runs the project's own code and sign-in. You said yes to this update and to the helper install.

## What Changes

- **What you get: relay-ring's schedules start again.** relay-ring gets its own background helper. It starts with the computer and runs only relay-ring's schedules and Inbox taps. Another project's update can't stop them again.
  ```text
  Before                     After
  ------                     -----
  shared helper              relay-ring's own helper
  (ClaymooApp's copy)
    Keep my chats in line      Keep my chats in line
    ⚠ Needs your OK            ✓ handed to a chat
  ```
- **What you get: a clear reason when a run can't sign in.** When this computer isn't signed in to the app, the Inbox says so, not *Needs your OK*, and asks for no OK. The browser update also means another chat's browser turn never stops this chat's own tab.
  ```text
  Inbox › Schedules › Keep my chats in line
    09:15  didn't start, this computer isn't signed in
  ```
- **What changes in how you work.** Nothing you type changes. Your OKs stay, so you approve nothing again. Runs that already started and open Inbox taps move to the new helper, so nothing runs twice.
  ```text
  Your OKs ............ kept (one file for all projects)
  Started runs ........ move to relay-ring's helper
  Open Inbox taps ..... move too, each arrives once
  ```
- **What of yours stays.** Relay Everything's app, server, website, phone app and plugin do not change. The public plugin list still shows only the Relay Everything plugin. None of the 22 changed WongStack files has a local edit here, so nothing needs a merge.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, server, site,
  phone app and plugin
  Public plugin list: Relay Everything only
  ```
- **What is left out, and why.** The update check names the public plugin list as an old WongStack plugin. It is Relay Everything's own list, so it stays, as in the last two updates. Codex on this computer has no old WongStack plugin, so that step removes nothing. The shared helper keeps running for the other projects that have no helper of their own. WongStack's own helper and its open pull request belong to another chat.
  ```text
  Checked, nothing to do:
    public plugin list ...... Relay Everything's own, kept
    old Codex plugins ....... none left
    shared helper ........... stays for other projects
  ```
- **What you do yourself.** Nothing. After the update is live, I install relay-ring's helper at a quiet minute, not on a 5-minute mark. Then I check, within 10 minutes, that the next line-up run went to a chat and that the Inbox shows a run, not *Needs your OK*.
  ```text
  1. publish the update
  2. install relay-ring's helper    (e.g. 17:57, not 17:55)
  3. next line-up run → handed      (Inbox shows a run)
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.5.0 at commit `a43bb2af` on this computer.
- **Your yes to install the helper**: Ready. You said yes to this update and to the helper install.
- **The main relay-ring folder up to date**: Ready. Its auto-sync timer moves it to the published code; the install refuses older code, so the task waits for it.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes only WongStack's shared tools, and no requirement in `openspec/specs/` (checked: `relay-inbox` is Relay Everything's email notes, not WongStack's Inbox). The change sets `skip_specs: true`.

## Impact

- 22 of 772 WongStack parts changed (preflight `status: update`, `catchUp.needed: true` for `module-plugin` on `.claude-plugin/marketplace.json` only, `updatingComplete: true`): all `modified` and `installed-equivalent`, so all copy whole. Groups are in the design.
- The admin app's Inbox (`app/src/apps/inbox/cadence.ts`) gets one new reason, `not_signed_in`; it ships with the app's normal deploy.
- A new systemd service on this computer, `wongstack-helper@relay-ring-<code>.service`, outside the repository.
- No settings, hook, route, `relay_*` table, memory database or plugin change.

## Decision log

- **2026-11-13** — Assumed: install the helper and publish the update with no further question, because the person already said yes to both (the request that started this chat).
- **2026-11-13** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement names the background helper or WongStack's Inbox; `relay-inbox` covers email notes.
- **2026-11-13** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-13** — Assumed: keep `.claude-plugin/marketplace.json`, which the catch-up names, because it lists only the Relay Everything plugin; `.claude/settings.json` has no `enabledPlugins` or `@skills-dir` key and each module hook once, so the `module-plugin` move has nothing else to do.
- **2026-11-13** — Assumed: run the install from the main folder `/root/relay-ring`, not this workspace, because the helper's launcher starts it from the main project folder, and a workspace goes away at close.
- **2026-11-13** — Assumed: run the site and server publish scripts after the publish, because `AGENTS.md` asks for both after each publish; they report the result even though no `site/` or server file changes.
- **2026-11-13** — Assumed: run `codex-plugin.mjs` as the last repo task, as `/wong-sync` asks, because `--check` prints nothing: it removes nothing here.
- **2026-11-13** — Check: the shared helper's `folders.json` lists `/root/relay-ring`, and `wongos` and `wongstack` already run their own `wongstack-helper@…` services, so relay-ring is the one left on the shared helper.
- **2026-11-13** — Assumed: the after-publish steps (group 4) carry no tick box and `/ship`'s own `/save` replaces task 3.2, because `/ship` archives the plan before the merge; the shipping chat runs group 4 after `finish`.
- **2026-11-13** — Assumed: the dry-run (was task 2.4) moves into after-publish step 4.3, because `helper.mjs install --dry-run` reads the main folder `/root/relay-ring`, which holds 61.3.0 until the merge; before then it prints `HELPER=outdated` and changes nothing. The shipping chat runs the dry-run first in step 4.3, as the design's install steps do.
- **2026-11-13** — Assumed (second look): step 4.4 also passes on a `no_work` run, which the Inbox counts as a quiet check, not a run, because the line-up finds nothing to do when no chat needs lining up; it fails only on *Needs your OK* or *not signed in*.
- **2026-11-13** — Archived inside `/ship` at `openspec/changes/archive/2026-11-13-wongstack-61-5-update`, branch `neat-donkey`: 22 WongStack parts copied and equal to `install-path.mjs`, merge check `clean`, Inbox tests 32/32, public check, product-name test and wiki checks pass, the install record says 61.5.0 and the preflight reports `status: current`; Codex had no WongStack plugin. The second look found one wording gap in step 4.4, fixed. Group 4 runs after the merge.
