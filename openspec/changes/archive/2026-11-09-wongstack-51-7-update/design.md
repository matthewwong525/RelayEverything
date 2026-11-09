# Design

## Context

See proposal.md, Why. Source: `/root/WongStack` at `a8a601a0b48dd724d48ebaf7ec0808891f7c56e2` (51.7.0), clean and equal to `origin/main` on 2026-11-09. Installed: `3ee8c0f97091af2831f42120d889babfd9a62759` (51.4.0). The preflight (`/tmp/wong-preflight.json`; re-run if gone) found 25 changed units of 669, all `modified`, `catchUp.needed: false`, no diagnostics. `CLAUDE.md` already links to `AGENTS.md`.

Logical `.claude/` paths below live in the real `.agents/` folder; source paths are the same under the source's `.agents/`.

## The update units

**Modified, installed-equivalent (12): copy from the source; `drawings.md` then takes the moved tip (see `wiki/review-pages.md` below).**

- `.claude/skills/apply/scripts/preview-review.mjs`
- `.claude/skills/daily/scripts/chats.mjs`, `chief.mjs`, `todos.mjs` (51.5.0: a schedule's chat waits until it stops)
- `.claude/skills/explore/scripts/step-title.mjs`
- `.claude/skills/plan/SKILL.md`, `plan/references/drawings.md`, `plan/references/review-kit.html`, `plan/scripts/build-review.mjs`, `plan/scripts/prototype.mjs` (51.6.0, 51.7.0: review cards; `prototype.mjs serve`; the no-real-picture warning)
- `.claude/skills/schedule/scripts/lib/app-runs.mjs`
- `wiki/stack/host-schedules.md`

**Locally adapted, close rule only (9): take upstream's file or block whole.** Each held only this repo's 51.4.0-era close rule, and 51.5.0 ships the same rule in its own words.

- `AGENTS.md` `WONG-STACK` block (the *One task, one workspace* line; the rest of the block and every line outside it stay)
- `.claude/skills/explore/references/asking-the-user.md`
- `.claude/skills/lesson/SKILL.md`
- `.claude/skills/plan/references/new-workspace.md` (drops the local *`/verify` walk* choice from the Paseo close question)
- `.claude/skills/schedule/scripts/tidy.mjs` (only the top comment differs)
- `.claude/skills/ship/SKILL.md`
- `wiki/development/first-day/make-a-change.md`
- `wiki/development/required-tools.md`
- `wiki/development/the-change-loop.md` (also takes upstream's `/close` bullet: *wraps up a chat you chose to close*)

**Locally adapted, with a local line kept (4): merge.**

- `wiki/development/browsing.md`: take upstream's `agent-browser --profile <temp folder>` sentence; keep `## When your turn holds the browser`.
- `wiki/development/daily.md`: take upstream's *A schedule's chat waits until it stops* bullet, *once it stops* in the handoff paragraph, and its *Close finished chats* paragraph (no tidy-up sentence); keep the `ship-every-chat.md` line.
- `wiki/review-pages.md`: take upstream's page whole. This repo's tip, **Open it in a browser before you build the page** (the builder does not run the script; a browser's own top-level name such as `top` stops it), moves to a line under the `live` fence item of `.claude/skills/plan/references/drawings.md`: upstream's page is 2,995 words, and the tip takes it past the 3,000-word cap. So `review-pages.md` is a plain copy, and `drawings.md` is the locally adapted unit instead.
- `wiki/ux-principles.md`: take upstream's page whole, then put back *Relay Everything's own palette, type and screen rules are on [the brand page](brand.md).* after the Refactoring UI sentence.

**Hand steps.** 51.7.0, 51.6.0: rebuild open plans' pages; `openspec list` shows none open, so nothing. 51.6.1: every `agent-browser` use here is in a payload file. 51.5.0: nothing.

## Decisions

**Upstream's close wording replaces the local one.** The rule is the same: a finished chat in Paseo asks, closes only on a yes, never at a review, mid-build or on a problem, and the tidy-up closes no chat. Alternative considered: keep the local words. Rejected: nine files stay locally adapted for no change in behavior, and each sync must merge them again.

**`tidy.test.mjs` stays.** This repo's own test (in `app/package.json`'s `node --test` list) checks that the sweep archives no workspace; upstream's `tidy.mjs` behaves the same, so the test must still pass unchanged.

## Risks / Trade-offs

- [A copy drops a local line] → the merge check (`merge-check.mjs --from 3ee8c0f…`) names any missing added line; the design names the expected drops (the local close wording).
- [The new review kit breaks this repo's page builds] → task 3.2 builds this change's own page with the new builder.

## Migration Plan

Copy, take, merge, check, then `/save`. Rollback: revert the pull request.
