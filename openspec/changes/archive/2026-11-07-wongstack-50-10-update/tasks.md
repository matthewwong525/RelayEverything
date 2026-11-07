# Tasks

## 1. Copy the unchanged-locally units

- [x] 1.1 Copy the 68 modified/installed-equivalent files from the source to the target, `AGENTS.md`'s WongStack block included as a block-only replace; verify each target blob now equals the source blob (`git hash-object` compare) and the Relay Everything block of `AGENTS.md` is unchanged.
- [x] 1.2 Copy the 28 added files listed in the design; verify each exists with the source's content.

## 2. Merge the browser

- [x] 2.1 Merge `.claude/skills/browser/scripts/browse.mjs` and `browser-server.mjs` by the design: take the window, tab, add-on and identity hunks; keep the route forwarder, proxy-line reader, `network off` and the `BROWSE_NETWORK=`/`BROWSE_LANGUAGE=` status; leave out the `proxy [on|off]` setting.
- [x] 2.2 Merge `.claude/skills/browser/SKILL.md`, `wiki/development/browsing.md` and the new `wiki/development/browser-window.md`, pointing proxy wording at `wiki/development/browser-proxy.md`.

## 3. Merge the app and wiki units

- [x] 3.1 Merge `app/package.json` (two new checks in `test`), `app/knip.jsonc`, `app/worker-configuration.d.ts` (`WONG_KEY_SEAL_PUBLIC`) and `app/worker/keys.test.ts`, keeping this repo's lines.
- [x] 3.2 Merge `app/tests/employee-access/connections.ts` (core list with `sealed_keys`, then this repo's loop) and `app/tests/runtime/runtime.test.ts` (upstream entry shape, `RELAY_CHECKER_SHA256` kept, `apps/relay.ts` imported).
- [x] 3.3 Merge `wiki/development/daily.md` and `wiki/stack/README.md`, keeping this repo's lines.

## 4. Relay Everything's real-database test

- [x] 4.1 Write `app/tests/runtime/apps/relay.ts` with the three cases in the design (no sign-in refused, a key adds only to its own space, another person's key cannot reach it), adding local-only harness bindings if the space needs them.

## 5. The seal pair

- [x] 5.1 Ask once, then run `node scripts/seal-keys.mjs pair`: `WONG_KEY_SEAL_PUBLIC` lands in `app/wrangler.jsonc` and `WONG_KEY_SEAL_PRIVATE` on GitHub; verify `gh secret list` names it and no output shows the private half.

## 6. Verify

- [x] 6.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target . --source /root/.cache/wong-stack/WongStack --from 0f492d5d543a22190e3b075ab49757a63dbe8808`; take every missing hunk, or name each one left out on purpose (the `proxy` setting lines), until only those remain.
- [x] 6.2 Run `npm test` in `app/` (with `check-runtime-tests.mjs` and `check-service-definitions.mjs`), `node --test .claude/skills/browser/scripts/*.test.mjs`, and `node scripts/public-check.mjs --tree`; verify all pass with no check loosened.
- [x] 6.3 Run `node .claude/skills/browser/scripts/browse.mjs status`; verify it still prints `BROWSE_NETWORK=`.
- [x] 6.4 Rerun the preflight; verify every unit is `latest-equivalent` or `locally-adapted` with only the named browser lines missing.
- [x] 6.5 Run `/save` and verify the pull request's checks pass and the staging preview opens.

## 7. Install record

- [x] 7.1 Set `.claude/.wong-stack.json` `version` to `50.10.0` and `commit` to `1d14a762d2bc132ed78f054aec8adeca3cb4e406`, and add `services` to `components.skills`, keeping every other key; verify the JSON parses and the preflight reports `status: current` or only the named browser lines.
