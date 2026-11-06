# Design: Update WongStack to 50.1.0

## Context

See proposal.md, Why. Source: `/root/.cache/wong-stack/WongStack` at `0f492d5d543a22190e3b075ab49757a63dbe8808` (VERSION 50.1.0), refreshed by fast-forward on 2026-11-06. Installed: 48.2.0 at `113599351893bc6ba7fc77c22fab5babb1df9c42`. The preflight (schema 1, `status: update`, all four categories, `catchUp.needed: false`, no diagnostics, 990 ms) found 163 changed units. Its full report is `/tmp/tmp.6PPq7dksE6/p.json`; rerun the preflight if that file is gone.

`CLAUDE.md` already links to `AGENTS.md`, and `.claude` links to `.agents`. Logical `.claude/…` paths below are real files under `.agents/…`.

## Goals / Non-Goals

- Goal: every changed unit takes the 50.1.0 version, or a merge of it with Relay's own lines.
- Non-goal: any Relay behavior change, any Relay website page, or the WongOS browser proxy (the other chat builds on this after it is live).

## Decisions

### Unit routes, by preflight class

| Class | Count | Route |
|---|---|---|
| modified / installed-equivalent | 111 | Copy the source file over the target file. |
| added / missing | 26 | Copy, except the `.pyc` below (25 copied). |
| removed / installed-equivalent | 19 | Delete the target file. |
| modified / locally-adapted | 7 | Apply the upstream hunk from 48.2.0 to 50.1.0 by hand; keep Relay's lines. |

Copy, not three-way merge, is safe for the installed-equivalent class: the target blob equals the 48.2.0 blob, so no local line is lost.

Removed (19): `.claude/skills/browser/scripts/logins.mjs`; `.claude/skills/hand-over/scripts/{form-page.html,form-page.mjs,form.mjs,passwords-page.html,passwords-page.mjs,passwords.mjs,picture-view.mjs}`; `.claude/skills/save/references/schedule-records.md`; `.claude/skills/save/scripts/schedule-record.mjs`; `.claude/skills/schedule/references/definition.md`; `.claude/skills/schedule/scripts/lib/{lifecycle.mjs,move.mjs}`; `openspec/schemas/scheduled-work/{schema.yaml,templates/binding.json,templates/proposal.md,templates/tasks.md}`; `wiki/development/{passwords.md,private-form.md}`.

Added (25 copied): `.claude/skills/browser/scripts/addons.mjs`; `.claude/skills/connect/{SKILL.md,scripts/browser.mjs,scripts/mask-keys.mjs}`; `.claude/skills/daily/scripts/schedule-runs.mjs`; `.claude/skills/schedule/scripts/lib/{app.mjs,approvals.mjs,move-in.mjs,version.mjs}`; `app/src/apps/inbox/{Schedules.tsx,Schedules.test.tsx,cadence.ts,cadence.test.ts}`; `app/worker/apps/inbox/{schedule-approved.ts,schedule-progress.ts}`; `app/worker/employee-access/{tools.ts,tools-route.ts,tools-route.test.ts}`; `app/worker/key-rules.ts`; `schema/migrations/{20261105120000_tools.sql,20261106120000_schedule_definitions.sql}`; `wiki/development/{password-manager.md,saved-details.md,watch-link.md}`; `wiki/stack/connect-your-tools.md`.

### The stray cache file

Skip `.claude/skills/browser/scripts/__pycache__/launch-config.cpython-314.pyc`. It is Python's compiled cache of `launch-config.py`, listed in the 50.1.0 inventory by mistake. Alternative: copy it to match the inventory exactly. Rejected: a binary cache goes stale with its source and the next preflight would only flag it as missing, which is harmless.

### The seven locally-adapted units

Each upstream hunk is small (1 to 25 lines). Relay's lines stay:

- `app/worker/index.ts`: add the `keyed` helper and its imports (`withTools`, `humanEmail`, `AccessIdentity`); wrap `env` for Access, discovery, services and the app API. Keep Relay's own routes.
- `app/worker/index.test.ts`: the two `withSession` counts rise (3 → 6, 14 → 18) upstream. Relay's local tests add routes, so recount Relay's numbers by the same rule (each signed Access, discovery and services request reads tools once) and take the number the test run proves.
- `app/tests/employee-access/connections.ts`: add the two new migration names to the list; keep Relay's extra migrations.
- `schema/seed.sql`: replace Fay's schedules block with the new columns and rows; keep Relay's seed rows.
- `wiki/development/daily.md`, `wiki/stack/README.md`, `wiki/stack/mini-apps.md`: take the upstream wording; keep Relay's lines and links.

`merge-check.mjs --from 113599351893bc6ba7fc77c22fab5babb1df9c42` proves no added upstream line is missing before the record moves.

### The WongStack block

Replace only the text between `WONG-STACK:BEGIN` and `WONG-STACK:END` in `AGENTS.md` with the source block. The Relay ring and context sections above it stay. Three rule lines change (Simplified English wording; the keys line now points to connect-your-tools; the browse line to live-view).

### Links to removed pages

Relay-owned text must not link to `wiki/development/passwords.md` or `private-form.md`. After the copy, `grep` the repo outside `openspec/changes/archive/` for those names, `schedule-record`, `form-page` and `scheduled-work`; fix any Relay-owned link to its new home (`live-view.md`, `saved-details.md`, `host-schedules.md`).

## Risks / Trade-offs

- [The public check refuses a copied file, for example an example email or address in a new seed or test] → run `node scripts/public-check.mjs --tree`; on `result=refused`, take the detail out of the file and record the hunk dropped; never weaken the check.
- [New migrations fail on production data] → they only add tables and columns; the staging publish applies them first by the data pipeline.
- [Relay's `index.test.ts` counts differ from upstream's] → let the run decide; each change of count gets the upstream comment's reason.
- [The other chat's browser proxy plan conflicts] → the person chose update first; that chat rebases after this is live.

## Migration Plan

1. Publish through the normal gate (CI on the pull request); staging and production take the two migrations.
2. After it is live: ask once whether to delete `~/.wong-stack/logins.json` (50.0.0). Delete only on yes; it can not be undone.
3. After it is live: run the 49.0.0 schedule move by the source's `.claude/skills/schedule` move-in step; expect nothing to move (no `schedules/`, no `.agents/daily/`, empty list). If something appears, follow the step's duplicate question and the small save it names.
4. Tell the person they can say *connect my tools* (48.3.0).

Rollback: revert the merge commit. The new tables stay unused; they are additive.
