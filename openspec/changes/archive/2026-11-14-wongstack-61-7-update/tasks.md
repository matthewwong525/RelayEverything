# Tasks

## 1. Copy WongStack 61.7.0

- [x] 1.1 Rerun the preflight to `.scratch/wong-preflight.json` (design §Context) and confirm 29 changed units at commit `ea0af925`. Copy every `installed-equivalent` and `added` unit by `install-path.mjs` to its `targetPath`, and delete `.claude/skills/browser/addon/bell.svg`. Verify: each copied file equals `install-path.mjs` output.
- [x] 1.2 Merge the four `locally-adapted` units by hand (design §The changed parts) and link the design guide from `wiki/README.md`. Verify: each upstream added line is present, and local text stays.
- [x] 1.3 Set the Emerald accent in `app/src/index.css` and add the admin app to `wiki/brand.md`'s colour homes (design §The accent). Verify: the six values match the table.

## 2. Check

- [x] 2.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target <this checkout> --source /root/.cache/wong-stack/WongStack --from a43bb2affdc367c3f36a5e99bcaea8cd47f1ec7b`. Verify: exit 0, or each missing line is named and taken or left on purpose.
- [x] 2.2 In `app/`, run `npm run lint`, `npx vitest run src/style.test.ts`, and the type check; from the root, `node scripts/check-app-checks.mjs`. Verify: all pass.
- [x] 2.3 Run `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks `.github/scripts/checks.mjs` runs. Verify: all pass.
- [x] 2.4 Rebuild this plan's page (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 3. Record

- [x] 3.1 Set `version` to `61.7.0` and `commit` to `ea0af925ebc4bd64d086c6e66e48f33747841251` in `.claude/.wong-stack.json`, keeping every other key. Then run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/codex-plugin.mjs` in this checkout. Verify: the preflight run again reports `status: current`, and the Codex helper removes nothing.

## 4. After publish

`/ship` archives this plan before the merge, so these steps carry no box. The shipping chat runs them after `finish` and reports each result.

- 4.1 After the merge to `main`, run `node scripts/publish-relay-site.mjs`, then `node scripts/publish-relay-server.mjs`. Verify: report both `result=` lines.
