# Design

## Context

See proposal.md, Why. Source: `/root/.cache/wong-stack/WongStack` at `3ee8c0f97091af2831f42120d889babfd9a62759` (51.4.0); installed `57208cc11cf518670ca7dcfeeba6c73ffd9d2c3a` (51.0.0). The preflight (`/tmp/wong-preflight.json`, re-run if gone) found 38 changed units of 669, `catchUp.needed: false`. `CLAUDE.md` already links to `AGENTS.md`.

Logical `.claude/` paths below live in the real `.agents/` folder; source paths are the same under the source's `.agents/`.

## The update units

**Modified, installed-equivalent (33): copy from the source.**

- `.claude/hooks.json`, `.claude/settings.json` (51.4.0 adds a `PreToolUse` entry for `AskUserQuestion`; this repo's copy has no local edits, so the copy keeps it)
- `.claude/skills/browser/SKILL.md`, `browser/scripts/browse.mjs`, `connect/scripts/browser.mjs`
- `.claude/skills/daily/references/briefs/line-up.md`, `briefs/stop-judge.md`, `references/chief.md`
- `.claude/skills/daily/scripts/chief.mjs`, `daily.mjs`, `line-up-check.mjs`, `line-up.mjs`, `stop-check.mjs`, `transcript.mjs`
- `.claude/skills/explore/references/asking-the-user.md` (then the local edit below), `explore/scripts/ask-check.mjs`
- `.claude/skills/hand-over/scripts/hand-over.mjs`, `lib/inbox.mjs`, `reply-link.mjs`, `view-page.mjs`
- `.claude/skills/plan/scripts/build-review.mjs`, `schedule/scripts/schedule.mjs`
- `.claude/skills/ship/SKILL.md` (then the local edit below), `ship/scripts/ship.mjs`
- `.claude/skills/wong-sync/references/payload-files.json`
- `wiki/development/browser-window.md`, `live-view.md`, `login-codes.md`, `password-manager.md`, `reply-links.md`, `watch-link.md`
- `wiki/stack/connect-your-tools.md`, `wiki/stack/host-schedules.md`

**Added (3): copy.** `.claude/skills/daily/scripts/chat-list.mjs`, `daily/scripts/waiting-notes.mjs`, `wiki/development/chats-in-line.md`.

**Locally adapted (2): merge.**

- `wiki/development/browsing.md`: take upstream's two rewritten bullets (*How a link closes*, *After it closes*); keep this repo's `## When your turn holds the browser` section.
- `wiki/development/daily.md`: take upstream's check-ins lines (tap answers, *Obvious pick*), the short *Your chats in line* section that links `chats-in-line.md`, and the *Tell* line; keep the `ship-every-chat.md` line. Then the local edit below.

**Hand steps.** 51.1.0: no own skill or page runs `hand-over.mjs` with `--until*` or `--keep-open` outside the payload; `wiki/development/secrets.md` waits on a key link, which still prints `done`. 51.4.0: covered by the settings copy. Others: none.

## The local rule: a chat closes only on the person's pick

### Decisions

**The finished-chat question replaces the unasked `/close`.** In a Paseo worktree, finished work ends with the question tool: *Close this chat (Recommended)* and *Keep it open*, plus any routine or app offer and, after `/ship`, a `/verify` walk. *Close this chat* runs `/close`. Outside Paseo or in the main checkout, no close option. Alternative considered: keep the unasked close and add an undo. Rejected: Paseo archives the workspace, and the person asked for no automatic close.

Edits:

- `AGENTS.md`, `WONG-STACK` block: *One task, one workspace.* A finished task asks once whether to close its Paseo workspace through `/close`, beside any routine or app offer; nothing closes it unasked. A new task opens a new workspace.
- `wiki/development/the-change-loop.md#one-task-one-workspace`: done, the agent asks *Close this chat* (recommended) or *Keep it open*, after any offer, and runs `/close` only on that pick; the existing *never at a plan's review…* limits stay as limits on when the question is asked.
- `.claude/skills/explore/references/asking-the-user.md`: drop *finished work that closes* from the no-question list; the Paseo-worktree bullet becomes *Close this chat (Recommended)* / *Keep it open*, plus any offer.
- `.claude/skills/plan/references/new-workspace.md#next-work`: in a Paseo worktree, open and report each part, then ask *Close this chat (Recommended)*, a `/verify` walk, or *Keep it open*. Outside Paseo, unchanged.
- `.claude/skills/ship/SKILL.md` Step 6: a failed live look, or a `/ship` that `/close` invoked, asks no close question.

**The tidy-up stops closing idle workspaces.** `tidy.mjs sweep` drops `sweepWorkspaces` and its call; it still stops orphan processes under worktree parents, deletes old temp and scratch files, and writes its report. Delete helpers only `sweepWorkspaces` used (`isIdle`, idle-only parts of `listAgents` if unused); keep `ownWorkspace`, `savedState`, `mergedAtTip`, `pullRequest` and `BUSY`, which `close`, `close-child` and `daily/scripts/finished.mjs` use. `tidy.mjs close` stays: `/close` runs it. Alternative considered: a setting to turn the sweep's close on or off. Rejected: more code for a choice nobody asked for.

Docs: `wiki/development/required-tools.md` (two mentions: *the session-start tidy-up of idle workspaces*; *closes saved ones idle three days*) and `wiki/development/daily.md` (*The tidy-up still closes a saved chat idle for 3 days*) say that no chat closes by itself.

**Kept as is.** `daily` *What's going on?* close question, and `daily/scripts/todos.mjs` `keepChats`, which sends `/close` only to a chat the person closed in the Inbox.

### Test

`.claude/skills/schedule/scripts/tidy.test.mjs` (node:test): make a temp git repo with a linked worktree whose HEAD is old and saved; point `TIDY_PASEO_BIN` at a fake `paseo` that answers `ls`/`workspace ls`/`inspect` with that worktree as idle and logs every argument line to a file; run `tidy.mjs sweep`; assert the log holds no `workspace archive` and the report's `closed` is empty. Add the file to `app/package.json`'s `node --test` list.

## Risks / Trade-offs

- [Open chats pile up in Paseo] → *What's going on?* lists them and asks which to close.
- [A later sync overwrites the local rule] → each edited unit becomes `locally-adapted`; the merge check names these hunks. Note the rule in the final report and offer to send it upstream by hand ([contributing](../../../wiki/contributing.md)).
- [`asking-the-user.md` and `ship/SKILL.md` are copied, then edited] → copy first, then edit, so the merge check compares against 51.4.0.

## Migration Plan

Copy, merge, edit, test, then `/save`. Rollback: revert the pull request.
