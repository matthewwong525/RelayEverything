# Update WongStack to 51.10.0: questions in the chat, and clearer scheduled chats

**Status:** ready-to-ship
**Branch:** peachy-snake
**Open questions:** none

## Why

This repo runs WongStack 51.7.0, and 51.10.0 is out. It asks every planning question in the chat and keeps the review page for your final OK. It also gives each scheduled chat its own named workspace, and starts that chat with the words you approved.

## What Changes

- **What you get: questions come to you in the chat, and the review page is only for your OK.** Picks, typed answers, dates and a choice between pictures come as question cards before the page is made. The page shows the result: you read it, tap *OK*, and add notes if you want. Files you hand over, such as a logo, stay on the page under *What the build needs*. Every card on a computer now has the same width, and the plan's link is one line: *👉 Tap here to see the plan*.
  ```picture
  Before, phone: pictures/before-phone.png
  After, phone: pictures/after-phone.png
  ```
- **What you get: scheduled chats that are easy to find and start right.** A chat that a schedule starts opens in its own workspace, named after the schedule, such as *Wiki tidy*, not *main*. It works on a fresh copy of the project, never on the main copy. Its first message is the instructions you approved, word for word, with a short footer. A schedule that is still running opens no second chat: the Inbox shows *didn't start, it's already running*.
  ```text
  Today                  After
  -----                  -----
  Workspace: main        Workspace: Wiki tidy
  Main copy              Fresh copy
  Fixed first message    Your instructions
  Runs can overlap       "already running"
  ```
- **What changes in how you work.** Nothing you type changes. A plan asks its questions before it shows you the page, so you answer in the chat, then look the page over.
  ```text
  Questions in the chat
  -> Review page
  -> OK or notes
  -> Build
  ```
- **What of yours stays.** Relay Everything's app, website and server do not change. The screen rules keep their link to the Relay Everything brand page. The plan's drawing guide keeps your tip to open a sample page in a browser before you build the plan's page.
  ```text
  Kept as they are
  ----------------
  Relay Everything app, site, server
  Brand page link in the screen rules
  "Open a sample in a browser first" tip
  ```
- **What is left out, and why.** No Relay Everything website page changes, because this update changes only the assistant's own tools. WongStack's own tests and sample plans stay in WongStack, because they test WongStack itself.
  ```text
  Copied: 19 WongStack parts with no local edits
  Merged: 2 parts with your edits
  Left in WongStack: its tests and sample plans
  ```
- **What you do yourself.** Nothing, unless a chat that a schedule opened is still open: close it, and its next run starts the new way. The build lists any such chat for you.
  ```text
  You: say yes
  Then: build, check, publish, refresh the main copy
  ```

## What the build needs

- **The WongStack source**: Ready, at version 51.10.0 on this computer.
- **The main project folder on this computer**: Ready. It has only new, unsaved folders (`cad/`, `vendor/`), so it can take the published update without losing them.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools, not a Relay Everything behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 21 changed WongStack parts from the update check: 19 with no local edits (copy), 2 with local edits (merge): `.claude/skills/plan/references/drawings.md` and `wiki/ux-principles.md`. Lists are in the design.
- Scheduled runs on this computer start through the helper, which runs from the main project folder (`/root/relay-ring`). That folder is behind `main`, so after publishing it takes a fast-forward and the helper restarts.
- Non-goals: no Relay Everything feature, website page or `relay_*` table change.

## Decision log

- **2026-11-10** — Asked to update from WongStack 51.7.0 to 51.10.0 and stop at the plan for a yes → planned the full update; the build waits for Matthew's yes.
- **2026-11-10** — Assumed: keep the *open it in a browser before you build the page* tip under the drawing guide's `live` line, renamed upstream to *A site or tool*, because the builder still does not run a card's script.
- **2026-11-10** — Assumed: keep the brand-page link in `wiki/ux-principles.md` and take upstream's new *Close stands alone* rule and preview-page wording, because neither touches the local line.
- **2026-11-10** — Assumed: nothing to do for 51.8.0's note, because no open plan in this repo or its workspaces has a `form` fence.
- **2026-11-10** — Assumed: no other file needs the removed schedule commands, because only `hosts.mjs`, which the copy replaces, names `schedule.mjs start`.
- **2026-11-10** — Assumed: after publishing, fast-forward the main project folder and restart the helper, because the helper starts scheduled runs from that folder, which is still at #79, before even the 51.7.0 update; its changes are only untracked folders.
- **2026-11-10** — Assumed: no spec delta (`skip_specs: true`) and no website page change, because no Relay Everything behavior changes.
- **2026-11-10** — Assumed: no overlap with other workspaces, because their plans change the phone app, Settings, the plugin and voice notes, not WongStack's files.
- **2026-11-10** — Assumed: `CLAUDE.md` needs no move, because it already links to `AGENTS.md`.
- **2026-11-10** — Assumed: show WongStack's own before and after pictures of a review page, because they are the closest real result and this repo's plan pages use the same kit.
- **2026-11-10** — Assumed: inside `/ship`, the post-merge steps (republish the site and server, fast-forward `/root/relay-ring`, restart the helper) run after `finish` as the design's Migration Plan says, not as tasks, because `/ship` archives only a change with every task ticked.
- **2026-11-10** — Built inside `/ship`: 19 files copied, 2 merged, install record at 51.10.0. Merge check clean, preflight `current`, local checks pass, second look found nothing. No scheduled chat is open. Saving for task 3.2.
