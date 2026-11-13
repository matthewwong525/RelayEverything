# Update WongStack to 61.3.0: a bell on each tab that waits on you, emoji chat names, and 1Password passkeys

**Status:** ready-to-ship
**Branch:** sync-wongstack-source
**Open questions:** none

## Why

This repo runs WongStack 61.0.0, and 61.3.0 is out. The agent's browser now shows which tabs wait on you and lets you hand back all of them with one click. Chat names start with one emoji for the build step. The agent can sign in with 1Password's icon and with a passkey saved in 1Password, after your yes.

## What Changes

- **What you get: a bell on each tab that waits on you, and one *Hand back* button.** When a sign-in, a payment, a robot check or a stuck step needs you, that chat's tab shows 🔔 in its title. One *Hand back* button at the top of the browser counts the waiting tabs and ends every open turn with one click. Two chats can now wait on you at the same time.
  ```text
  ┌─ Browser ─────────────────── [ Hand back (2) ] ─┐
  │ 🔔 Sign in – Stripe │ 🔔 Checkout – JLC │ Docs    │
  └─────────────────────────────────────────────────┘
  ```
- **What you get: 1Password sign-in with its icon and passkeys.** When 1Password's list does not open, the agent clicks its small icon in the email box. A passkey saved in your 1Password works too: the agent asks you first, and presses sign-in only after your yes. It closes 1Password's *Save login?* boxes by itself and never saves anything to your vault.
  ```text
  Agent: Sign in to Stripe with the passkey
         "Stripe login" from 1Password?      [ Yes ] [ No ]
  ```
- **What changes in how you work: chat names start with an emoji.** The name shows the build step as one emoji, not a capital word. Other commands, such as `/verify` or `/schedule`, keep the chat's name. Open chats move to the emoji at their next step.
  ```text
  Before                          After
  ------                          -----
  PLAN: Fix the invoice total     📝 Fix the invoice total
  SHIP: Fix the invoice total     🚀 Fix the invoice total
  VERIFY: …                       (name stays)
  ```
- **What of yours stays.** Relay Everything's app, server, website, phone app and plugin do not change. The public plugin list still shows only the Relay Everything plugin. Each WongStack check still runs once per chat. None of the 23 changed WongStack files has a local edit here, so nothing needs a merge.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, server, site, phone app, plugin
  Public plugin list: Relay Everything only
  One copy of each WongStack check
  ```
- **What is left out, and why.** The update check names the public plugin list as an old WongStack plugin. It is Relay Everything's own list, so it stays, as in the last update. Codex on this computer already has no old WongStack plugin, so the Codex step has nothing to remove. No publish of the website or server is needed, because their files do not change.
  ```text
  Checked, nothing to do:
    public plugin list ........ Relay Everything's own, kept
    old Codex plugins ......... none left
    website and server ........ no file changes
  ```
- **What you do yourself.** Nothing. The *Hand back* button shows after the browser's next start; until then, say *done* in each chat to end its turn.
  ```text
  You:        say yes
  The build:  copy 23 files, check, save
  After:      browser restarts → Hand back button shows
  ```

## What the build needs

- **The WongStack source**: Ready, version 61.3.0 at commit `102e1abb` on this computer.
- **Codex on this computer**: Ready. Its check found no old WongStack plugin (Decision log).

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes only WongStack's shared tools, and no requirement in `openspec/specs/` (checked: `browser-proxy`, `relay-chats`). The change sets `skip_specs: true`.

## Impact

- 23 of 772 WongStack parts changed (preflight `status: update`, `catchUp.needed: true` for `module-plugin` on `.claude-plugin/marketplace.json` only, `updatingComplete: true`): 20 modified and 3 added, all `installed-equivalent` or `missing`, so all copy whole. Groups are in the design.
- Browser module 3.0.0 → 3.2.0 (new `addon/` folder: `background.js`, `bell.svg`, `manifest.json`); Daily 4.0.0 → 4.1.0; `.claude/loop/step-title.mjs`; `wiki/development/the-change-loop.md`.
- No settings, hook, app, route, `relay_*` table, memory database or plugin change. No `relay:api-doc` run and no site or server publish.

## Decision log

- **2026-11-13** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything requirement names browser hand-over, 1Password or chat names; `browser-proxy` covers only the home proxy, which this update does not touch.
- **2026-11-13** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-13** — Assumed: keep `.claude-plugin/marketplace.json`, which the catch-up names, because it lists only the Relay Everything plugin and no WongStack module; `.claude/settings.json` has no `@skills-dir` key and each module hook once, so the `module-plugin` move has nothing else to do.
- **2026-11-13** — Assumed: the three releases' hand steps need nothing, because each says *nothing to do by hand*.
- **2026-11-13** — Assumed: nothing outside the payload reads the old `PLAN: ` style names, because a search of `app`, `mobile`, `site`, `plugin`, `scripts`, `wiki` and `knowledge` finds them only in the payload page `wiki/development/the-change-loop.md`, and this repo has no copy of WongStack's tests.
- **2026-11-13** — Assumed: run `codex-plugin.mjs` as the last task, as `/wong-sync` asks, because `--check` prints nothing: it removes nothing and adds nothing here.
- **2026-11-13** — Check: the merge check from `9d63c758` is `clean` with 0 files, because no changed unit is locally adapted.
- **2026-11-13** — Built inside `/ship`: preflight 23 units at `102e1abb`, all copied by `install-path.mjs` and equal to its output; merge check `clean`; public check, product-name test and the wiki and skills checks pass; a fresh `claude -p` chat ran every hook with exit 0 and named itself with the 🔨 emoji; the install record says 61.3.0, the preflight reports `status: current`, and `codex-plugin.mjs` found no WongStack plugin to remove. The second look found nothing.
