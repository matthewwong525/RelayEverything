# Tasks

## 1. Copy the unchanged-locally units

- [x] 1.1 Copy the 33 modified/installed-equivalent files listed in the design from the source to the target; verify each target blob equals the source blob (`git hash-object` compare).
- [x] 1.2 Copy the 3 added files; verify each exists with the source's content, and `.claude/settings.json` holds the `PreToolUse` entry for `AskUserQuestion`.

## 2. Merge the locally-adapted units

- [x] 2.1 Merge `wiki/development/browsing.md` by the design; verify the two upstream bullets are present and `## When your turn holds the browser` is kept.
- [x] 2.2 Merge `wiki/development/daily.md` by the design; verify the `ship-every-chat.md` line is kept and the page stays under 3,000 words.

## 3. A chat closes only on the person's pick

- [x] 3.1 Edit `AGENTS.md`'s *One task, one workspace* line, `wiki/development/the-change-loop.md#one-task-one-workspace`, `.claude/skills/explore/references/asking-the-user.md`, `.claude/skills/plan/references/new-workspace.md#next-work` and `.claude/skills/ship/SKILL.md` Step 6 by the design; verify `grep -rn "unasked\|ask nothing" AGENTS.md wiki/development/the-change-loop.md .claude/skills/plan/references/new-workspace.md .claude/skills/explore/references/asking-the-user.md` finds no rule that runs `/close` without the question, and `node scripts/product-name.test.mjs` passes.
- [x] 3.2 Remove `sweepWorkspaces` and its idle-only helpers from `.claude/skills/schedule/scripts/tidy.mjs`; keep `close`, `close-child` and the helpers `daily/scripts/finished.mjs` imports; verify `node .claude/skills/schedule/scripts/tidy.mjs sweep --dry-run` exits 0 and `node --check` passes on `tidy.mjs` and `daily/scripts/finished.mjs`.
- [x] 3.3 Write `.claude/skills/schedule/scripts/tidy.test.mjs` by the design and add it to `app/package.json`'s `node --test` list; verify it passes now and fails when the old `sweepWorkspaces` call is put back.
- [x] 3.4 Update the idle-close mentions in `wiki/development/required-tools.md` and `wiki/development/daily.md`; verify `grep -rn "idle three days\|idle for 3 days\|tidy-up of idle" wiki` finds nothing.

## 4. Verify

- [x] 4.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target /root/.paseo/worktrees/11511sre/calm-fly --source /root/.cache/wong-stack/WongStack --from 57208cc11cf518670ca7dcfeeba6c73ffd9d2c3a`; take every missing hunk, or name each one this repo drops on purpose (the auto-close lines), until no other remains.
- [x] 4.2 Run `npm test` in `app/` and `node scripts/public-check.mjs --tree`; verify all pass with no check loosened.
- [x] 4.3 Run `/save`; verify the pull request's checks pass.

## 5. Install record

- [x] 5.1 Set `.claude/.wong-stack.json` `version` to `51.4.0` and `commit` to `3ee8c0f97091af2831f42120d889babfd9a62759`, keeping every other key; verify the JSON parses and the preflight reports no `added` or installed-equivalent `modified` unit, only the locally-adapted ones from this change.
