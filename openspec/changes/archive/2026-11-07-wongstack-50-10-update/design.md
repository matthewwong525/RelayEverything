# Design: Update WongStack to 50.10.0

## Context

See proposal.md, Why. Source: `/root/.cache/wong-stack/WongStack` at `1d14a762d2bc132ed78f054aec8adeca3cb4e406` (VERSION 50.10.0), refreshed by fast-forward on 2026-11-07 (already up to date). Installed: 50.1.0 at `0f492d5d543a22190e3b075ab49757a63dbe8808`. The preflight (schema 1, `status: update`, categories core, ui, pack and scaffold, `catchUp.needed: false`, no diagnostics, 763 ms) found 108 changed units of 687. Its full report is `/tmp/wong-preflight-50.10.0.json`; rerun the preflight if that file is gone.

`CLAUDE.md` already links to `AGENTS.md`, and `.claude` links to `.agents`, in both the source and this repo. Logical `.claude/…` paths below are real files under `.agents/…`.

## Goals / Non-Goals

- Goal: every changed unit takes the 50.10.0 version, or a merge of it with this repo's own lines.
- Goal: the new app check `scripts/check-runtime-tests.mjs` passes, with a real-database test for the `relay` part.
- Non-goal: any Relay Everything behavior change, any website page, or a change to the browser's proxy routes (`openspec/specs/browser-proxy`).

## Decisions

### Unit routes, by preflight class

| Class | Count | Route |
|---|---|---|
| modified / installed-equivalent | 68 | Copy the source file over the target file; the `AGENTS.md` block replaces only its block. |
| added / missing | 28 | Copy. |
| modified / locally-adapted | 12 | Apply the upstream hunk from 50.1.0 to 50.10.0 by hand; keep this repo's lines. |

No unit is removed in this range. Copy is safe for the installed-equivalent class: the target blob equals the 50.1.0 blob, so no local line is lost.

Added (28): `.claude/skills/daily/references/briefs/line-up.md`, `.claude/skills/daily/references/schedules.json`, `.claude/skills/daily/scripts/{line-up.mjs,line-up-check.mjs}`, `.claude/skills/schedule/scripts/lib/defaults.mjs`, `.claude/skills/services/SKILL.md`, `app/src/lib/{seal.ts,seal.test.ts}`, `app/tests/runtime/apps/{access.ts,hello.ts,inbox.ts,knowledge.ts}`, `app/tests/runtime/{budget.ts,context.ts,services.ts}`, `app/tests/runtime/fixtures/services/example/{openapi.json,examples/things.json}`, `app/worker/api/forward-exchange.test.ts`, `app/worker/employee-access/{keys-route.ts,keys-route.test.ts}`, `schema/migrations/20261106130000_sealed_keys.sql`, `scripts/{check-runtime-tests.mjs,check-service-definitions.mjs,lib-openapi.mjs,lib-scrub.mjs,lib-services.mjs,seal-keys.mjs}`, `wiki/development/browser-window.md`.

The full modified list is the preflight report's `changes`.

### The twelve locally-adapted units

- **Browser** (`.claude/skills/browser/SKILL.md`, `scripts/browse.mjs`, `scripts/browser-server.mjs`): take 50.5.0 to 50.8.0's one window with a tab per chat, the `front` command, the window setting, add-ons side by side, the real system identity, and the removed password-manager question. Keep this repo's `forwarder.mjs` routes (first, upstream, direct), the proxy-line reader in `server.mjs`, `network off`, and the `BROWSE_NETWORK=` and `BROWSE_LANGUAGE=` status lines. Where upstream starts `startProxy(proxySetting())`, start this repo's route forwarder as before. Leave out the `proxy [on|off]` command, the `proxy` key in `SETTINGS`, and the `running.proxy` restart test; the 50.5.0 restart test keeps only the window part. `forwarder.mjs`, `server.mjs`, `lib/` and their tests are not in the update and stay as they are.
- **`wiki/development/browsing.md`** and the new **`wiki/development/browser-window.md`**: take the upstream text, but replace "the proxy is off unless turned on" wording with a link to [`browser-proxy.md`](../../../wiki/development/browser-proxy.md), which owns this repo's routes. One topic, one page.
- **`wiki/development/daily.md`**, **`wiki/stack/README.md`**: take the upstream wording; keep this repo's lines and links.
- **`app/package.json`**: add `node ../scripts/check-runtime-tests.mjs` after `npm run test:runtime`, and `node ../scripts/check-service-definitions.mjs` after `check-app-keys.mjs`, in the `test` script. Keep this repo's `public-check`, `product-name`, plugin and self-host tests and the `relay:api-doc` script. Take any upstream dependency bump.
- **`app/knip.jsonc`**: add upstream's new entries; keep this repo's.
- **`app/worker-configuration.d.ts`**: add `WONG_KEY_SEAL_PUBLIC` (and any other new upstream binding); keep the `RELAY_*` bindings. Regenerate with `wrangler types` if the repo's script does so, then check the diff only adds.
- **`app/tests/employee-access/connections.ts`**: take the core migration list line as WongStack has it, with the new `sealed_keys` migration; keep the second loop for this repo's migrations (decided in the 50.1.0 update).
- **`app/tests/runtime/runtime.test.ts`**: take upstream's new entry shape, which imports each `apps/<name>.ts` and runs it on the seeded database. Keep `RELAY_CHECKER_SHA256` in the start variables and add an import of the new `apps/relay.ts`.
- **`app/worker/keys.test.ts`**: take upstream's new cases; keep this repo's `RELAY_*` key entries.

### The 50.2.2 pretend-database removal

`fakeDatabase` appears only in four upstream files that this update replaces (`app/worker/api/discovery.test.ts`, `app/worker/employee-access/key-levels.test.ts`, `app/worker/employee-access/policy.test.ts`, `app/tests/env.ts`). No `app/worker/apps/relay` test uses it, so no own test needs the one-line helper.

### The relay real-database test (50.2.0)

`check-runtime-tests.mjs` fails when an `app/worker/apps/<name>/` with an `api.ts` has no `app/tests/runtime/apps/<name>.ts` imported by the entry. `relay` has `api.ts`. Write `app/tests/runtime/apps/relay.ts` in the shape of `apps/inbox.ts`, starting from `resetToSeed` and the `relay_people` rows in `schema/seed.sql`:

1. A route under `/apps/relay/` with no sign-in and no key gets 401, and writes nothing.
2. A device key made for a seeded person checks itself with `GET key` and adds a note to that person's space only.
3. A second person's key cannot read or add to the first person's space.

If the runtime harness lacks a binding the space needs (the notes bucket or a Durable Object), add it to `startRuntime` the way upstream's `setup.ts` adds its own, local-only and with no secret. If a case cannot run in the harness, keep the others and say which case is left to the unit tests in `app/worker/apps/relay/isolation.test.ts`.

### The seal pair (50.4.0)

`node scripts/seal-keys.mjs pair` writes `WONG_KEY_SEAL_PUBLIC` into `app/wrangler.jsonc`'s top-level `vars` and sets `WONG_KEY_SEAL_PRIVATE` as a GitHub secret (this repo publishes through `.github/workflows/deploy.yml`). Ask once before it runs: it sets a secret on GitHub. The public half is safe in a public repo; run `node scripts/public-check.mjs --tree` after to prove it passes. If the check refuses the value, stop and report: never weaken the check. Never print the private half.

### The WongStack block

Replace only the text between `WONG-STACK:BEGIN` and `WONG-STACK:END` in `AGENTS.md` with the source block. The Relay Everything block above it stays.

### The install record

Set `version` to `50.10.0` and `commit` to `1d14a762d2bc132ed78f054aec8adeca3cb4e406` in `.claude/.wong-stack.json`. Add `services` to `components.skills`, at its place in the source list. Every other key stays.

## Risks / Trade-offs

- [The browser merge drops a home-route line] → run `node --test .claude/skills/browser/scripts/*.test.mjs` and `browse.mjs status`; it must still print `BROWSE_NETWORK=`. The spec `browser-proxy` stays the test.
- [A later WongStack browser update conflicts again with the local routes] → accepted until WongStack ships its home-proxy plan; then a sync replaces the local route code.
- [The new migration's date sorts before this repo's later migrations] → Wrangler applies every migration not yet listed in its own table, by name, so the older-dated file still applies once; it only adds a table.
- [The relay runtime test needs bindings the harness lacks] → add local-only bindings, or narrow the cases, as above.
- [The public check refuses a copied file or the public seal half] → on `result=refused`, take the detail out and record it; never weaken the check.

## Migration Plan

1. Publish through the normal gate (CI on the pull request); staging and production take the `sealed_keys` migration.
2. Nothing by hand after it is live. The next chat adds the two default schedules (50.9.0), paused if check-ins are off (50.10.0). The next browser start takes the new window; this Linux computer keeps its device identity (50.6.2), and the proxy routes stay on.

Rollback: revert the merge commit. The `sealed_keys` table stays unused; it is additive. Remove `WONG_KEY_SEAL_PRIVATE` from GitHub only if the pair is made again.
