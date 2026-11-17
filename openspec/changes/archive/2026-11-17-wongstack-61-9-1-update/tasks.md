# Tasks

## 1. Copy WongStack 61.9.1

- [x] 1.1 Copy the 17 `installed-equivalent` and `latest-equivalent` units by `install-path.mjs` to their `targetPath`, and delete `.claude/skills/plan/scripts/prototype.mjs` (design §The changed parts). Verify: each file equals `install-path.mjs` output.
- [x] 1.2 Merge the three `locally-adapted` units (design §The merged parts). Verify: each differs from `install-path.mjs` output only by its kept local lines.

## 2. Phone screen pictures

- [x] 2.1 Update `.agents/skills/plan/SKILL.md`, `.agents/rules/mobile.md` and `wiki/development/phone-pictures.md` (design §61.9.0's target impact). Verify: no file outside the archive sends a plan to a screen test or names `prototype.mjs` or `No real picture`.

## 3. Check

- [x] 3.1 Run `node /root/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target <this checkout> --source /root/WongStack --from 1c4c6663c687f370c694222e877b8fb88ee1d2c5`. Verify: every reported hunk is taken or is a named local choice in the design.
- [x] 3.2 Run `node --check` on each copied script, `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks `.github/scripts/checks.mjs` runs. Verify: all pass.
- [x] 3.3 Rebuild this plan's page (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 4. Record

- [x] 4.1 Set `version` to `61.9.1` and `commit` to `88730bbac893cf8fbdc5fc8c3de036b2e78c7063` in `.claude/.wong-stack.json`, keeping every other key. Then run `node /root/WongStack/.claude/skills/wong-sync/scripts/codex-plugin.mjs` in this checkout. Verify: the preflight run again reports `status: current`, and the Codex helper removes nothing.

## 5. After publish

`/ship` archives this plan before the merge, so these steps carry no box. The shipping chat runs them after `finish` and reports each result.

- 5.1 After the merge to `main`, run `node scripts/publish-relay-site.mjs`, then `node scripts/publish-relay-server.mjs`. Verify: report both `result=` lines.
- 5.2 Once `/root/relay-ring` is at the new `main`, at a minute not ending in 0 or 5, run `node .claude/skills/reply-link/scripts/helper.mjs install` there. Verify: it reports the helper running.
