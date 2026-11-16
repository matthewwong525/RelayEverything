# Tasks

## 1. Copy WongStack 61.7.2

- [x] 1.1 Copy the five `installed-equivalent` units by `install-path.mjs` to their `targetPath` (design §The changed parts). Verify: each file equals `install-path.mjs` output.

## 2. Check

- [x] 2.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target <this checkout> --source /root/.cache/wong-stack/WongStack --from ea0af925ebc4bd64d086c6e66e48f33747841251`. Verify: exit 0.
- [x] 2.2 Run `node --check` on both copied scripts, `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks `.github/scripts/checks.mjs` runs. Verify: all pass.
- [x] 2.3 Rebuild this plan's page (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 3. Record

- [x] 3.1 Set `version` to `61.7.2` and `commit` to `1c4c6663c687f370c694222e877b8fb88ee1d2c5` in `.claude/.wong-stack.json`, keeping every other key. Then run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/codex-plugin.mjs` in this checkout. Verify: the preflight run again reports `status: current`, and the Codex helper removes nothing.

## 4. After publish

`/ship` archives this plan before the merge, so these steps carry no box. The shipping chat runs them after `finish` and reports each result.

- 4.1 After the merge to `main`, run `node scripts/publish-relay-site.mjs`, then `node scripts/publish-relay-server.mjs`. Verify: report both `result=` lines.
