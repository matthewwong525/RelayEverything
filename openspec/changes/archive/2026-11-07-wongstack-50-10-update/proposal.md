# Update WongStack to 50.10.0

**Status:** ready-to-ship
**Branch:** wongstack-50-10-update
**Open questions:** none

## Why

This repo runs WongStack 50.1.0. Nine releases came out since then (50.2.0 to 50.10.0). They let the assistant send a key to your app sealed, so nobody can read it on the way. They also give the assistant one browser window with a tab for each chat, and tell your chats each other's news.

## What Changes

- **What you get.** When the assistant connects a tool, or you paste a key in Access, the key goes to your app sealed. The next publish opens it and puts it in the app's secrets. Each outside service keeps the calls the assistant worked out, with examples, in one place. The assistant's browser has one window with a tab for each chat, and it can add any browser add-on you ask for. Each chat hears the other chats' news through two schedules that the next chat adds by itself.
  ```mermaid
  flowchart TB
    A["Key from a tool or Access"] --> B["Sealed on the way"]
    B --> C["Waits in the app"]
    C --> D["Next publish puts it in"]
  ```
- **What changes in how you work.** The app's checks now also test each part of the app on a real local database, filled with sample rows. Relay Everything's own server part gets this test too, so a fault in it shows before a publish, not after.
  ```text
  Before                 After
  ------                 -----
  Tests with pretend     Tests on a real local
  databases              database with sample rows
  Relay Everything's     Relay Everything's part
  part: no such test     gets its own test
  ```
- **What of yours stays.** All of Relay Everything stays as it is: the phone app, the website, the server pages and the person spaces. The assistant's browser keeps its home routes: the home computer first, the backup service second, then this computer's own network. WongStack's new switch that turns the proxy off by default does not come in, because you want every browser to go through the home proxy. The few shared files that Relay Everything changed keep their lines and get the new lines too.
- **What is left out, and why.** WongStack's own home-proxy plan has not come out yet, so this repo keeps its own route code. A later update can swap to WongStack's when it comes. No Relay Everything website page changes, because the update changes the assistant's tools, not what the website describes.
- **What you do yourself.** Nothing by hand. During the build, the assistant asks once before it makes your app's pair of locks for sealed keys. One half goes in the app's settings and the other half is a GitHub secret. Until then, the app refuses a sealed key and says so; keys saved before stay working.

## What the build needs

- **The WongStack source**: Ready, at version 50.10.0 on this computer.
- **GitHub login to set a secret**: Ready, the `gh` login on this computer. The build asks once before it sets the secret.
- **Cloudflare and app keys**: Ready, in `.env`.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools, not a Relay Everything behavior in `openspec/specs/`. The browser keeps every `browser-proxy` requirement as it is. The change sets `skip_specs: true`.

## Impact

- 108 changed WongStack parts from the update check: 68 changed with no local edits, 28 new, 12 changed where this repo has its own edits. Lists are in the design.
- One new app table, `sealed_keys`, from migration `20261106130000_sealed_keys.sql`. The publish applies it to staging and production by the normal data pipeline.
- `AGENTS.md`'s WongStack block changes; the Relay Everything block above it stays.
- A new skill, `services`, joins the install record.
- A new real-database test, `app/tests/runtime/apps/relay.ts`, for the `relay` app part, which `scripts/check-runtime-tests.mjs` now requires.
- Non-goals: no Relay Everything feature change, no website page, no change to the browser's proxy routes.

## Decision log

- **2026-11-07** — Assumed: keep this repo's home-proxy routes, proxy-line reader and `BROWSE_NETWORK=` status on top of WongStack's new browser, because Matthew settled that on 2026-11-07 (fact #240) and WongStack 50.10.0 still has no first or upstream routes.
- **2026-11-07** — Assumed: leave out WongStack 50.5.0's `proxy on|off` setting (off by default), because Matthew wants every browser to go through the home proxy, and this repo's `network off` already gives a way to go direct.
- **2026-11-07** — Assumed: make the seal pair during the build, after one confirm, because its public half goes in `app/wrangler.jsonc`, which this change must carry, and setting a GitHub secret is an outward step.
- **2026-11-07** — Assumed: write a small real-database test for the `relay` part (sign-in refusals, a device key adding to its own space, and one person not reaching another's space), because the new check fails without one, and these are the server's core promises.
- **2026-11-07** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything capability changes behavior.
- **2026-11-07** — Assumed: no Relay Everything website page changes, because the update changes the assistant's tools, not the app, server, ring or connections that the website describes.
- **2026-11-07** — Assumed: add `services` to `components.skills` in `.claude/.wong-stack.json`, because the update installs that new skill; every other key stays.
- **2026-11-07** — Assumed: no other workspace overlaps this update, because the open workspaces change the phone app, webhooks, texting and Pebble parts, not WongStack's shared files.
- **2026-11-07** — Asked whether to set the `WONG_KEY_SEAL_PRIVATE` GitHub secret during the build → chose set it now.
- **2026-11-07** — Asked whether to delete Apple's *Created via API* development certificates so main's iPhone build passes → chose delete and continue; only two remained and another run was using them, so none were deleted while main's rerun was watched.
- **2026-11-07** — Check: `.github/workflows/deploy.yml` adds the *Put waiting keys* step with `continue-on-error: true`, because WongStack 50.4.0 lets the release stand when a sealed key can not open: the step names the key and warns, and the key stays waiting.
- **2026-11-07** — Check: `app/.jscpd.json` ignores `worker/services/**`, because those files are answer types made from `schema/services/<key>/`, not code anyone writes (WongStack 50.x).
- **2026-11-07** — Check: `app/knip.jsonc` adds `worker/services/*.ts` as an entry, because a made service's answer type that no code reads yet must keep its type (WongStack 50.x).
- **2026-11-07** — Check: `app/package.json` changes the `test` chain only to add `check-runtime-tests.mjs` and `check-service-definitions.mjs`; no check goes out.
- **2026-11-07** — Assumed: the `relay` real-database test runs on the runtime as it is, with no SPACES binding, because staging's company app has none either: it checks callers on the real `relay_people`, `relay_keys` and `relay_sessions` rows (no sign-in refused, a phone key held to its own routes, a turned-off or unknown key refused, only the owner joins, a session's change only from the page) and that a preview opens no space. A note landing in its own space, and one person never reaching another's, stay with `app/worker/apps/relay/isolation.test.ts`. Adding a spaces Worker would change WongStack's shared `setup.ts`.
- **2026-11-07** — Assumed: `browse.mjs status` prints `BROWSE_NETWORK=` and `BROWSE_LANGUAGE=` before the install check, then upstream's window, shown and add-on lines, and leaves out `BROWSE_PROXY=`, because the browser-proxy spec needs the route line even when the browser is stopped.
- **2026-11-07** — Assumed: drop upstream's `startProxy` helper and its *proxy off* advice in `browsing.md`, `browser-window.md` and the browser skill, because every start here goes through the route forwarder; merge-check names only those lines, the `APPS` line with `relay`, the test chain line, and the made `worker-configuration.d.ts` values.
- **2026-11-07** — Assumed: make `worker-configuration.d.ts` with the pinned `wrangler types` and an empty env file, because this worktree's `.dev.vars` would add the five `RELAY_*` secret names that the committed file never held.
- **2026-11-07** — Assumed: move this repo's *Ship every chat from one chat* section from `wiki/development/daily.md` to its own page, `ship-every-chat.md`, because upstream's new text put `daily.md` at 3,021 words, over the 3,000-word cap.
- **2026-11-07** — Save checkpoint: built (95 files copied, 12 merged by hand, a relay real-database test, the seal pair made), reviewed with no findings, preflight now current; main's iPhone build passed on its rerun, so no Apple certificate was deleted.
- **2026-11-07** — Assumed: save on a new branch, `wongstack-50-10-update`, because `sync-wongstack-upstream` already shipped as PR #15 for the 50.1.0 update.
- **2026-11-07** — Archive checkpoint: all tasks done, PR #39 checks passed on f103868, the staging preview answered 200, and the change is archived for the ship.
