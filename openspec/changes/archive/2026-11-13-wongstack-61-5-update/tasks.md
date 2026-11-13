# Tasks

## 1. Copy WongStack 61.5.0

- [x] 1.1 Rerun the preflight to `.scratch/wong-preflight.json` (design §Context) and confirm 22 changed units at commit `a43bb2af`, none `locally-adapted`. Copy every unit by `install-path.mjs` to its `targetPath`. Verify: each of the 22 files equals `install-path.mjs` output, and `git status` shows no other changed file except this change's folder.

## 2. Check

- [x] 2.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target <this checkout> --source /root/.cache/wong-stack/WongStack --from 102e1abbe5d7b156d067431b4e166f5c5bb768db`. Verify: exit 0, `status: clean`.
- [x] 2.2 Run the admin app's Inbox tests in `app/` (`cadence.test.ts`, `Schedules.test.tsx`, `worker/apps/inbox/schedules.test.ts`). Verify: all pass.
- [x] 2.3 Run `node scripts/public-check.mjs`, `node scripts/product-name.test.mjs`, and the wiki and payload link checks `.github/scripts/checks.mjs` runs. Verify: all pass.
- [x] 2.5 Rebuild this plan's page with the builder (`build-review.mjs <change-root> --require-current`). Verify: it builds with no warning.

## 3. Record and save

- [x] 3.1 Set `version` to `61.5.0` and `commit` to `a43bb2affdc367c3f36a5e99bcaea8cd47f1ec7b` in `.claude/.wong-stack.json`, keeping every other key. Then run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/codex-plugin.mjs` in this checkout. Verify: the preflight run again reports `status: current`, and the Codex helper prints that nothing was removed.

## 4. After publish

`/ship` archives this plan before the merge, so these steps carry no box. The shipping chat runs them after `finish`, in order, and reports each result.

- 4.1 After the merge to `main`, run `node scripts/publish-relay-site.mjs`, then `node scripts/publish-relay-server.mjs`. Verify: report both `result=` lines.
- 4.2 Bring `/root/relay-ring` to the published commit (design §The helper install). Verify: its `.claude/.wong-stack.json` says `61.5.0`.
- 4.3 Run `node .claude/skills/reply-link/scripts/helper.mjs install --dry-run` in `/root/relay-ring` and check it names the `wongstack-helper@<id>` unit. Then, at a minute not on `:X0` or `:X5`, run `node .claude/skills/reply-link/scripts/helper.mjs install` in `/root/relay-ring`, then `status`. Verify: `HELPER=installed`, and `systemctl is-active wongstack-helper@relay-ring-<code>.service` prints `active`.
- 4.4 Within 10 minutes, read `~/.wong-stack/helpers/<id>/log.jsonl` and the admin app's Inbox › Schedules. Verify: the log shows the line-up run started by relay-ring's own helper, with outcome `handed` (or `no_work` when no chat needed lining up), and the Inbox shows that run, or its quiet-check count grows by one. It fails only on *Needs your OK* or *didn't start, this computer isn't signed in*.
