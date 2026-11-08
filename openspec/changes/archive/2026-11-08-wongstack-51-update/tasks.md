# Tasks

## 1. Copy, add and delete the unchanged-locally units

- [x] 1.1 Copy the 39 modified/installed-equivalent files from the source to the target; verify each target blob now equals the source blob (`git hash-object` compare).
- [x] 1.2 Copy the 9 added files listed in the design; verify each exists with the source's content.
- [x] 1.3 Delete the 33 removed files and the empty `app/src/apps/inbox/week/` and `app/worker/apps/inbox/tasks/` folders; verify `grep -rn "lib/board\|tests/board\|inbox/tasks/\|from \"./week" app` finds nothing.

## 2. Merge the locally-adapted units

- [x] 2.1 Merge `app/tests/employee-access/connections.ts` (add `20261107120000_inbox_chats.sql` to the core list; keep the `relay_*` loop) and `app/worker/api/contract.ts` (drop `checkerOwns`; keep the `typeof route === "function"` guard).
- [x] 2.2 Merge `schema/seed.sql`: append upstream's chats block; keep the `relay_people` checker row.
- [x] 2.3 Merge `wiki/development/daily.md` and `wiki/stack/mini-apps.md` by the design, keeping this repo's lines; verify `daily.md` stays under 3,000 words.

## 3. Verify

- [x] 3.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target . --source /root/.cache/wong-stack/WongStack --from 2acdf24b018a3596186316cc29a91ccfb40384b7`; take every missing hunk until none remain.
- [x] 3.2 Run `npm test` in `app/`, `node --test .claude/skills/daily/scripts/*.test.mjs` if any exist, and `node scripts/public-check.mjs --tree`; verify all pass with no check loosened.
- [x] 3.3 Rerun the preflight; verify every unit is `latest-equivalent` or `locally-adapted` with no missing hunk.
- [x] 3.4 Run `/save`; verify the pull request's checks pass and the staging Inbox opens on the chat list.

## 4. Before it goes live

- [x] 4.1 After the gate and before publish, run `company-api.mjs call inbox.daily-tasks` for the current week and the four before it; if any undone task is there, list it for Matthew, ask once which to keep, and make each named one a one-time schedule with `/schedule`. Verify each made schedule is listed, or record that the board was empty.

## 5. Install record

- [x] 5.1 Set `.claude/.wong-stack.json` `version` to `51.0.0` and `commit` to `57208cc11cf518670ca7dcfeeba6c73ffd9d2c3a`, keeping every other key; verify the JSON parses and the preflight reports `status: current`.
