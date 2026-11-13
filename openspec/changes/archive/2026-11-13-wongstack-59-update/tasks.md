# Tasks

## 1. Copy and remove WongStack 59.0.0

- [x] 1.1 Rerun the preflight to `.scratch/wong-preflight.json` (design §Context) and confirm 223 changed units at commit `facaf5f9`. Copy every `added`/`modified` unit that is `missing` or `installed-equivalent`, plus the 17 locally adapted files design §Merge list takes whole, by `install-path.mjs` to its `targetPath`; copy the `WONG-STACK` block into `AGENTS.md`. Verify: a sample of 20 units across browser, Daily, loop and memory equals `install-path.mjs` output; `git status` shows no file outside the preflight list except the planned edits.
- [x] 1.2 `git rm` the 52 `removed` units and remove the empty folders they leave (`.claude/skills/{continue,schedule,hand-over,shop}/`, `.claude/skills/memory/skills/dream-memory/`, `.claude/skills/memory/scripts/lib/documents/runtime/`). Verify: none of the paths exists.

## 2. Merge local lines and fix links

- [x] 2.1 Merge the six files in design §Merge list. Verify: `diff` against `install-path.mjs` output for each shows only the local line.
- [x] 2.2 Fix `wiki/development/README.md`, `app/package.json` and `.env.example` as design §Files outside the payload says. Verify: `grep` finds no `skills/schedule/`, `skills/hand-over/`, `skills/shop/` or `legacy-cloud-schedules` outside `openspec/changes/archive/` and the change folder.

## 3. The plugin's memory copy

- [x] 3.1 Drop the two gone folders from `LEFT_OUT` in `scripts/copy-plugin-memory.mjs`, run it, and raise `plugin/.claude-plugin/plugin.json` to 0.6.1. Verify: `node --test plugin/test/*.test.mjs` passes.
- [x] 3.2 Add the look-up count sentence to `plugin/README.md` and `site/src/content/docs/connections/claude-code.md` (design §The plugin's memory copy). Verify: `node scripts/product-name.test.mjs` passes.
- [x] 3.3 Trim the plugin's memory look-up counts to 30 days at each chat start, because the plugin runs no daily tidy, the one place the copy trims them; say so in the look-up count sentence. Verify: the chat-start test in `plugin/test/memory.test.mjs` fails without the trim and passes with it.

## 4. Check

- [x] 4.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target /root/.paseo/worktrees/11511sre/unruly-donkey --source /root/.cache/wong-stack/WongStack --from a282a4a936bc3b02b671682822bacfe82c255be1`. Verify: exit 0, or each missing hunk is taken or named in the Decision log.
- [x] 4.2 Run `npm test` in `app/`, `node scripts/public-check.mjs`, and the wiki and payload link checks the repo's CI runs. Verify: all pass.
- [x] 4.3 Start a fresh Claude Code chat in this checkout (`claude -p` with a one-word prompt). Verify: the memory start line prints, and `node .claude/skills/daily/skills/schedule/scripts/schedule.mjs list` lists the two schedules.
- [x] 4.4 Rebuild this plan's page with the copied builder (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 5. Record and publish

- [x] 5.1 Set `version` to `59.0.0` and `commit` to `facaf5f9ef5a5357c50b643feee275b6f994ec3e` in `.claude/.wong-stack.json`, keeping every other key. Do not run WongStack's Codex helper here (Decision log). Verify: the preflight run again reports `status: current`.
- [x] 5.2 After WongStack publishes *Sync unpacks nested commands*, refresh the source, rerun the preflight, and take its changes the same way (copy, remove, merge check), so `schedule`, `hand-over` and `shop` are top-level skill folders again; set the install record to that version and commit. Update the proposal's *how you work* bullet: `/schedule` stays. Verify: a fresh chat in this worktree lists WongStack's `schedule` skill, and the preflight reports `status: current`.
- [x] 5.3 After WongStack publishes *Every chat runs WongStack's hooks, with no plugins*, refresh the source, rerun the preflight, and take its changes the same way (copy, remove, merge check). Keep Relay Everything's public plugin list (`.claude-plugin/marketplace.json`) and one copy of each module hook in `.claude/settings.json` and `.codex/hooks.json`; drop the `enabledPlugins` lines. Follow its updating note and catch-up moves; run its Codex helper only if it removes WongStack's module plugins and adds none. Update the proposal's words, the design and the install record. Verify: the preflight reports `status: current`, the merge check is clean, and a fresh chat in this worktree prints the memory digest once and lists `schedule`.
- [x] 5.4 `/save`, then wait for CI on the pull request. Verify: every check passes.
