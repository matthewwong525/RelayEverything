# Update WongStack to 61.7.2: the ✅ button and pop-ups fit a phone's live view

**Status:** ready-to-ship
**Branch:** wong-sync-61-7-2-relay-everything
**Open questions:** none

## Why

This repo runs WongStack 61.7.0. Two small browser fixes came out since. 61.7.1 draws the *Hand back* button as the ✅ emoji itself. 61.7.2 makes pop-ups and the whole toolbar fit in a live view on a phone. You asked to update and publish.

## What Changes

- **What you get: the button looks exactly like ✅.** Each line says *tap ✅ at the top right*. The button there is now the same light green square with a white check, not a dark green circle. It still counts the tabs that wait on you, and it is grey when nothing waits.
  ```text
  Before:  [1Password] [(✓) 2]   dark green circle
  After:   [1Password] [✅ 2]    the ✅ emoji itself
  ```
- **What you get: pop-ups fit on a phone.** In a live view on your phone, a pop-up that opens past the right edge, such as 1Password's list or the browser's menu, moves left until it fits. The view also shows the browser window's full width, so the menu button shows. The page looks a little smaller.
  ```text
  Phone live view
  Before: [page ........|  1Password li|  ← cut off
  After:  [page ...  1Password list ]    ← whole
  ```
- **What changes in how you work.** Nothing. On a laptop the live view looks the same.
  ```text
  Laptop live view ... no change
  Phone live view .... pop-ups and toolbar fit
  ```
- **What of yours stays.** Everything. All five changed browser files have no local edits here, so each copies whole. The public plugin list still shows only the Relay Everything plugin. The website, server, phone app and plugin do not change.
  ```text
  Kept as they are
  ----------------
  Relay Everything site, server, phone app, plugin
  Public plugin list: Relay Everything only
  ```
- **What is left out, and why.** The update check names the public plugin list as an old WongStack plugin. It is Relay Everything's own list, so it stays, as in the last four updates. Codex on this computer has no old WongStack plugin, so that step removes nothing.
  ```text
  Checked, nothing to do:
    public plugin list ... Relay Everything's own, kept
    old Codex plugins .... none left
  ```
- **What you do yourself.** Nothing. The new button shows at the browser's next start.
  ```text
  1. publish the update
  2. next browser start → ✅ button
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.7.2 at commit `1c4c6663` on this computer.
- **Your yes to publish**: Ready. You asked to update and publish.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes only WongStack's shared browser tool, and no requirement in `openspec/specs/` covers it. The change sets `skip_specs: true`.

## Impact

- 5 of 774 WongStack parts changed (preflight `status: update`, `catchUp.needed: true` for `module-plugin` on `.claude-plugin/marketplace.json` only, `updatingComplete: true`): all 5 `modified` / `installed-equivalent`, copied whole. List in the design.
- No route, `relay_*` table, settings, hook, memory database, site, mobile or plugin change.

## Decision log

- **2026-11-16** — Assumed: build and publish with no further question, because Matthew asked to update and publish this repo now ("Ship wongstack in my 3 repos").
- **2026-11-16** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement covers WongStack's browser tool.
- **2026-11-16** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-16** — Assumed: keep `.claude-plugin/marketplace.json`, which the catch-up names, because it lists only the Relay Everything plugin ([WongStack updates](../../../../wiki/development/wongstack-updates.md)); no `enabledPlugins` `@skills-dir` key exists in `.claude/settings*.json`.
- **2026-11-16** — Found: `codex-plugin.mjs --check` prints nothing, so the last task removes nothing.
- **2026-11-16** — Assumed: run the site and server publish scripts after the publish, because `AGENTS.md` asks for both after each publish.
- **2026-11-16** — Archived inside `/ship` at `openspec/changes/archive/2026-11-16-wongstack-61-7-2-update`, branch `wong-sync-61-7-2-relay-everything`: 5 browser files copied equal to `install-path.mjs`, merge check clean, public check, product-name test and local checks pass, the install record says 61.7.2 and the preflight reports `status: current`; Codex had no WongStack plugin. The second look found nothing.
