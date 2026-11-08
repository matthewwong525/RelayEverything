# Update WongStack to 51.4.0, and no chat closes by itself

**Status:** ready-to-ship
**Branch:** stop-auto-closing-workspaces
**Open questions:** none

## Why

This repo runs WongStack 51.0.0, and 51.4.0 is out with six small fixes to questions, the browser and your chats. You also asked that no workspace close by itself: today a chat closes itself after it publishes, and the tidy-up closes a saved chat that sat idle for three days. From now on, a chat closes only when you say so.

## What Changes

- **What you get.** A question that needs you to open a link shows the link in the question. A chat that asks you in plain text asks again with buttons to tap. The daily keeps all your chats in line, in Paseo or not. A live view of the browser comes back only when you tap *Hand back*. A published plan leaves *Needs you* in the Inbox. The default schedules try their setup again when it fails.
  ```mermaid
  flowchart LR
    A["Chat asks in plain text"] --> B["Asks again with buttons"]
    C["Live view open"] --> D["Comes back on Hand back"]
    E["Plan published"] --> F["Leaves Needs you"]
  ```
- **What changes in how you work.** No chat closes by itself. When a chat finishes its work, it asks one question: *Close this chat* or *Keep it open*. It closes only on your tap. The tidy-up still deletes old scratch files, but it no longer closes idle chats.
  ```screen
  <div class="card col gap phone">
    <div>It is live. Notes now open after you save them.</div>
    <div class="sep"/>
    <div class="muted">What next?</div>
    <button class="btn-primary">Close this chat (Recommended)</button>
    <button class="btn-ghost">Keep it open</button>
  </div>
  ```
  ```text
  Before                   After
  ------                   -----
  Closes after publish     Asks: Close this chat?
  Idle 3 days: closed      Stays open
  "What's going on?" ask   Same
  Inbox "Close chat"       Same
  ```
- **What of yours stays.** All of Relay Everything stays as it is: the phone app, the website and the server. The browser page keeps its keyboard steps for when another chat holds the browser. The daily page keeps its link to shipping every chat from one chat. *What's going on?* still asks which finished chats to close, and *Close chat* in the Inbox still works.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, site, server
  Browser keyboard steps
  Ship every chat from one chat
  "What's going on?" close question
  ```
- **What is left out, and why.** No Relay Everything website page changes, because this update changes only the assistant's own tools. WongStack itself still closes chats by itself; this repo keeps its own rule, and a later update keeps it too. You can send the rule to WongStack by hand if you want it there.
  ```text
  WongStack (shared)          This repo
  ------------------          ---------
  Closes a finished chat      Asks first
  Closes idle chats           Leaves them open
  ```
- **What you do yourself.** Nothing. Chats that would have closed by themselves now stay open: close them from *What's going on?*, the Inbox, or each chat's last question.
  ```text
  Too many open chats?
    -> Say "What's going on?"
    -> Pick which to close
  ```

## What the build needs

- **The WongStack source**: Ready, at version 51.4.0 on this computer.
- **Paseo on this computer**: Ready, to try the close question in a workspace.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools and this repo's own chat rules, not a Relay Everything behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 38 changed WongStack parts from the update check: 33 changed with no local edits, 3 new, 2 changed where this repo has its own edits (`wiki/development/browsing.md`, `wiki/development/daily.md`). Lists are in the design.
- Local rule, protected at each later sync: `AGENTS.md` (the `WONG-STACK` block's *One task, one workspace* line), `wiki/development/the-change-loop.md`, `.claude/skills/explore/references/asking-the-user.md`, `.claude/skills/plan/references/new-workspace.md`, `.claude/skills/ship/SKILL.md`, `.claude/skills/schedule/scripts/tidy.mjs`, `wiki/development/required-tools.md`, `wiki/development/daily.md`.
- A new test, `.claude/skills/schedule/scripts/tidy.test.mjs`, joins the app's `npm test` chain.
- Non-goals: no Relay Everything feature, website page or `relay_*` table change.

## Decision log

- **2026-11-08** — Asked to stop workspaces closing by themselves, keeping the question to close → planned: a finished chat asks *Close this chat* / *Keep it open* and closes only on that tap.
- **2026-11-08** — Assumed: the three-day idle tidy-up stops closing chats too, because Matthew asked that nothing close a workspace by itself and the close question is enough.
- **2026-11-08** — Assumed: *What's going on?*'s close question and the Inbox's *Close chat* stay, because each closes only a chat the person picks.
- **2026-11-08** — Assumed: a chat outside Paseo or in the main checkout asks no close question, because it has no workspace to close.
- **2026-11-08** — Assumed: keep the 51.1.0 hand step as done by the copy, because only payload pages (`browser/SKILL.md`, `browser-window.md`) use `--keep-open`, and `wiki/development/secrets.md`'s `HANDOVER_RESULT=done` is a key link, not a live view.
- **2026-11-08** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything capability changes behavior.
- **2026-11-08** — Assumed: no Relay Everything website page changes, because the update changes the assistant's tools only.
- **2026-11-08** — Assumed: no overlap with other workspaces, because the open plans change the phone app and Settings, not WongStack's chat files.
- **2026-11-08** — Assumed: Lesson 2 ends with the same close question, not an unasked `/close`, because the second look found it still closed the chat by itself, against Matthew's ask.
- **2026-11-08** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-08** — Check: `app/package.json` adds `tidy.test.mjs` to the `node --test` list, because the new test must run in `npm test`. This makes the check stricter: nothing is turned off.
- **2026-11-08** — Built: 51.4.0 copied and merged; no chat closes by itself (close question in the rules and Lesson 2, idle close removed from the tidy-up, new `tidy.test.mjs`). Merge check: one hunk dropped on purpose, `asking-the-user.md`'s *finished work that closes* line. Local checks pass; saving inside `/ship`.
- **2026-11-08** — Archived for publish: task 4.3 passed (PR #74 checks SUCCESS at 4133e52).
