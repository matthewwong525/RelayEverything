# Tasks

## 1. Copy the unchanged-locally units

- [x] 1.1 Copy the 111 modified/installed-equivalent files from the source to the target, `AGENTS.md`'s WongStack block included as a block-only replace; verify each target blob now equals the source blob (`git hash-object` compare) and the Relay sections of `AGENTS.md` are unchanged.
- [x] 1.2 Copy the 25 added files listed in the design (not the `.pyc`); verify each exists with the source's content.
- [x] 1.3 Delete the 19 removed files listed in the design; verify none remains with `git ls-files`.

## 2. Merge the seven locally-adapted units

- [x] 2.1 Merge `app/worker/index.ts` (the `keyed` helper and its four call sites) and `app/tests/employee-access/connections.ts` (two migration names); verify `tsc -b` passes in `app/`.
- [x] 2.2 Merge `app/worker/index.test.ts`, recounting Relay's `withSession` numbers by the upstream rule; verify `vitest run app/worker/index.test.ts` passes.
- [x] 2.3 Merge `schema/seed.sql`'s schedules block, keeping Relay's rows; verify the seed loads after all migrations in a local D1 or SQLite run.
- [x] 2.4 Merge `wiki/development/daily.md`, `wiki/stack/README.md` and `wiki/stack/mini-apps.md`, keeping Relay's lines; verify the wiki link check passes.

## 3. Relay-owned references

- [x] 3.1 Search outside the archive for links to removed pages and scripts (`passwords.md`, `private-form.md`, `schedule-record`, `form-page`, `scheduled-work`); fix each Relay-owned one to its new home; verify the search finds only WongStack-owned text that the update itself ships.

## 4. Verify

- [x] 4.1 Run `node /root/.cache/wong-stack/WongStack/.claude/skills/wong-sync/scripts/merge-check.mjs --target . --source /root/.cache/wong-stack/WongStack --from 113599351893bc6ba7fc77c22fab5babb1df9c42`; take or name every missing hunk until it exits 0.
- [x] 4.2 Run `npm test` in `app/` and `node scripts/public-check.mjs --tree`; verify both pass, with no check loosened.
- [x] 4.3 Rerun the preflight; verify every unit but the skipped `.pyc` is `latest-equivalent` or `locally-adapted` with no missing upstream line.

## 5. Install record

- [x] 5.1 Set `.claude/.wong-stack.json` `version` to `50.1.0` and `commit` to `0f492d5d543a22190e3b075ab49757a63dbe8808`, keeping every other key; verify the JSON parses and the preflight reports `status: current` (or only the skipped `.pyc`).

