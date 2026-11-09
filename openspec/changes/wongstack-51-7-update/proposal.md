# Update WongStack to 51.7.0: clearer review pages, and WongStack now asks before it closes a chat

**Status:** ready-to-ship
**Branch:** famous-goose
**Open questions:** none

## Why

This repo runs WongStack 51.4.0, and 51.7.0 is out. It brings review pages that show the real screen first, an Inbox that shows a schedule's chat only when it needs you, and steadier browser checks. WongStack also now asks before it closes a chat, the same rule you asked for here on 8 November, so this repo can drop its own copy of that rule.

## What Changes

- **What you get: review pages that show the screen first.** A card's pictures sit side by side next to its words, as tall as the words, with no tabs. A click opens a picture full screen, and you swipe or use the arrow keys to see the next. On a phone, the words come first, then a row of small pictures. Each card has two buttons, *OK* and *Note*. A whole page, such as an email, gets its own card. A plan now warns when it shows a gray sketch with no real picture and does not say why.
  ```picture
  Before, computer: pictures/before-computer.png
  After, computer: pictures/after-computer.png
  After, phone: pictures/after-phone.png
  ```
- **What you get: a quieter Inbox and steadier browser checks.** A chat that a schedule opens stays out of the Inbox while it works. When it stops and stays open, such as after a failed run, it shows under *Working*, marked *From a schedule*. A browser check uses a browser of its own, so it no longer stops when another chat holds the shared browser.
  ```text
  Schedule run              Inbox
  ------------              -----
  Working                   (not shown)
  Stopped, still open       Working · From a schedule
  Closed by itself          (never shown)
  ```
- **What changes in how you work: the close question has new words, the same rule.** When a chat finishes, it asks *Close this chat?*, with *Close it* and *Keep it open*. It closes only on *Close it*. After a publish that opens other parts in new chats, the question no longer offers a check of the live site: ask for a check if you want one.
  No real picture: the close question is a card in the chat app, which this repo's prototype can not show.
  ```screen
  <div class="card col gap phone">
    <div>It is live. Notes now open after you save them.</div>
    <div class="sep"/>
    <div class="muted">Close this chat?</div>
    <button class="btn-primary">Close it (Recommended)</button>
    <button class="btn-ghost">Keep it open</button>
  </div>
  ```
  ```text
  Today                     After
  -----                     -----
  Close this chat           Close this chat?
                            -> Close it
  Keep it open              -> Keep it open
  Idle chats stay open      Idle chats stay open
  ```
- **What of yours stays.** Relay Everything's app, website and server do not change. The browser page keeps its keyboard steps for when another chat holds the browser. The daily page keeps its link to shipping every chat from one chat. The screen rules keep their link to the Relay Everything brand page. The plan's drawing guide keeps your tip to open a sample page in a browser before you build the plan's page.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, site, server
  Browser keyboard steps
  Ship every chat from one chat
  Brand page link in the screen rules
  "Open a sample in a browser first" tip
  ```
- **What is left out, and why.** No Relay Everything website page changes, because this update changes only the assistant's own tools. Nothing goes to WongStack by hand, because WongStack already has the close rule. WongStack's own tests and sample plans stay in WongStack, because they test WongStack itself.
  ```text
  Close rule
  ----------
  8 Nov: only this repo asks first
  51.5.0: WongStack asks first too
  Now: this repo uses WongStack's words
  ```
- **What you do yourself.** Nothing. No plan is open, so no review page needs a rebuild.
  ```text
  You: say yes
  Then: build, check, publish
  ```

## What the build needs

- **The WongStack source**: Ready, at version 51.7.0 on this computer.
- **Paseo on this computer**: Ready, for the Inbox and close-question parts.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools, not a Relay Everything behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 25 changed WongStack parts from the update check: 12 changed with no local edits (copy), 13 changed where this repo has its own edits (merge). Lists are in the design.
- Of the 13, 9 held only this repo's close rule, which upstream now has: they take upstream's text and become plain copies again. 3 keep a local line: `wiki/development/browsing.md`, `wiki/development/daily.md`, `wiki/ux-principles.md`. `wiki/review-pages.md` becomes a plain copy, and its tip moves to `.claude/skills/plan/references/drawings.md`.
- Non-goals: no Relay Everything feature, website page or `relay_*` table change.

## Decision log

- **2026-11-09** — Asked to update from WongStack 51.4.0 to 51.7.0 and stop at the plan's review page → planned the full update; build waits for Matthew's yes.
- **2026-11-09** — Assumed: take WongStack's close-question words (*Close this chat?* / *Close it* / *Keep it open*) in `AGENTS.md`, the change loop, the ask rules, the next-work rules, `/ship`, Lesson 2 and the first-day page, because 51.5.0 holds the same rule Matthew asked for on 2026-11-08 (closes only on a yes; the tidy-up closes no chat), and one wording avoids a local copy to protect at each sync.
- **2026-11-09** — Assumed: drop this repo's extra *check the live site* choice from the close question after next work, because upstream's ask has none and `/verify` stays one request away.
- **2026-11-09** — Assumed: take upstream's `tidy.mjs`, because it differs from this repo's copy only in its top comment.
- **2026-11-09** — Assumed: keep the *open it in a browser before you build the page* tip as its own bullet in the new live-card section of `wiki/review-pages.md`, because the builder still does not run a card's script.
- **2026-11-09** — Assumed: no hand step for 51.6.1, because every `agent-browser` use in this repo is in WongStack's own files, which the copy updates.
- **2026-11-09** — Assumed: no spec delta (`skip_specs: true`) and no website page change, because no Relay Everything behavior changes.
- **2026-11-09** — Assumed: no overlap with other workspaces, because the open plans change the website, the phone app and sign-in, not WongStack's files.
- **2026-11-09** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-09** — Assumed: show WongStack's own sample pictures of the new review card, because they are the closest real result and this repo's plan pages use the same kit.
- **2026-11-09** — Assumed: move the *open it in a browser before you build the page* tip from `wiki/review-pages.md` to the `live` fence line of the plan's drawing guide (`.claude/skills/plan/references/drawings.md`), because upstream's page is already 2,995 words and the tip takes it past the wiki's 3,000-word cap; the drawing guide is where a plan writes a live card, and `wiki/review-pages.md` becomes a plain copy again.
- **2026-11-09** — Built inside `/ship`: 51.7.0 copied and merged, install record at 51.7.0. Merge check clean, preflight `current`, local checks pass (one unrelated app test timed out once, then passed). Second look found no failures; saving for task 3.4.
