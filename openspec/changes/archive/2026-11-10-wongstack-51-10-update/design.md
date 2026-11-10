# Design

## Context

The install record (`.claude/.wong-stack.json`) says 51.7.0 at commit `a8a601a0`. The source checkout at `/root/.cache/wong-stack/WongStack` is at 51.10.0, commit `16a0af7e`. The preflight (`status: update`, 669 units, 21 changed, `catchUp.needed: false`) lists every change as `modified`.

Copy, installed-equivalent (19):

- `.claude/skills/apply/scripts/preview-review.mjs`
- `.claude/skills/explore/references/asking-the-user.md`
- `.claude/skills/explore/scripts/ask-check.mjs`
- `.claude/skills/hand-over/scripts/lib/helper-log.mjs`
- `.claude/skills/plan/SKILL.md`
- `.claude/skills/plan/references/review-kit.html`
- `.claude/skills/plan/scripts/build-review.mjs`
- `.claude/skills/schedule/references/run.md`
- `.claude/skills/schedule/scripts/lib/app-runs.mjs`
- `.claude/skills/schedule/scripts/lib/app.mjs`
- `.claude/skills/schedule/scripts/lib/hosts.mjs`
- `.claude/skills/schedule/scripts/schedule.mjs`
- `.claude/skills/schedule/scripts/workspace.mjs`
- `app/src/apps/inbox/cadence.ts`, `app/src/apps/inbox/cadence.test.ts`
- `wiki/development/reply-links.md`, `wiki/review-pages.md`, `wiki/stack/host-schedules.md`, `wiki/stack/live-line.md`

Merge, locally-adapted (2), from `merge-check.mjs --from a8a601a0`:

- `.claude/skills/plan/references/drawings.md`: take source lines 10-11 (`live` line now *A site or tool*; `form` line now *A needed file*, `file:` only). Keep the local indented tip under the `live` line.
- `wiki/ux-principles.md`: take source line 35 (*Close stands alone*) and line 86 (preview page: side by side, tap a spot). Keep the local brand-page sentence on line 23.

Source paths are under `.agents/` in the source; the target's `.claude` links to `.agents`.

## Goals / Non-Goals

**Goals:** the target matches 51.10.0 for every selected unit, with its 2 local lines kept; scheduled runs on this computer use the new runner after publishing.

**Non-Goals:** no source tests, sample plans, VERSION or changelog copied; no Relay Everything app, site or server behavior change.

## Decisions

- **Copy the 19 files byte for byte**, because their target blobs equal the installed source. Alternative: hand-merge each: needless, since none has local edits.
- **Merge the 2 adapted files by hand**, then run `merge-check.mjs` until it reports `status: ok`.
- **The inbox app takes the new `already_running` reason** through the copied `cadence.ts`; the Worker stores a run's reason as free text, so it needs no change (upstream changed no Worker file).
- **Refresh the main project folder after publishing.** The helper's launcher in `~/.wong-stack/helper/` starts the helper from `/root/relay-ring`, which is at #79. Its only changes are untracked `cad/` and `vendor/`, so `git pull --ff-only` is safe. Then restart `wongstack-helper.service` so the running helper loads the new `hosts.mjs`, `app-runs.mjs` and `workspace.mjs`. Alternative: leave it: scheduled runs would keep the old first message and the removed `schedule.mjs start`.

## Risks / Trade-offs

- [An open scheduled chat runs the removed `schedule.mjs start`] → the build lists open chats that a schedule started (Paseo `ls`), and the report asks Matthew to close each one.
- [The main folder gains local commits or edits before the pull] → `--ff-only` refuses; report it and leave the folder as it is.
- [A copied script needs a helper that changed upstream but is not in the list] → the preflight compares the full inventory, so none exists; the local checks and CI catch a missing import.

## Migration Plan

Copy and merge, run the checks, publish through `/ship`, then republish the site and server (per `AGENTS.md`), fast-forward `/root/relay-ring` and restart the helper. Rollback: revert the squash commit; the helper picks up the old code after the next pull and restart.
