# Update WongStack to 51.0.0

**Status:** ready-to-ship
**Branch:** wong-sync-51
**Open questions:** none

## Why

This repo runs WongStack 50.12.0. Release 51.0.0 changes the Inbox in your app: it now opens on a list of your open chats, and it shows which chat waits for you. The week board goes, because chats and schedules now do its work.

## What Changes

- **What you get.** The Inbox in your app opens on your chats. Each open chat is one row with its name, its step, such as *Plan*, and its folder. A chat that waits for your review is on top, under *Needs you*; a tap opens the review. Working chats come next, then an *Archive* of past reviews with a search. *Close chat* in a row's menu closes that chat when you have been quiet there for 15 minutes. A background schedule that finds something for you opens one chat with what it found. This is WongStack's screen, built and tested there, so the plan shows a sketch; the build's preview shows the real screen.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Inbox</h3><span class="grow"/><button class="btn-ghost">Schedules</button></div>
    <div class="muted">Needs you</div>
    <div class="row gap"><span class="grow">Weekly profit summary</span><span class="tag">Plan</span><span class="tag-outline">Review</span></div>
    <div class="sep"/>
    <div class="muted">Working</div>
    <div class="row gap"><span class="grow">Update WongStack to 51.0.0</span><span class="tag">Apply</span></div>
    <div class="row gap"><span class="grow">Voice notes on iPhone</span><span class="tag">Explore</span></div>
    <div class="sep"/>
    <div class="muted">Archive</div>
    <div class="field">Search past reviews</div>
  </div>
  ```
- **What changes in how you work.** The week board is deleted, with its days, tasks, backlog and week goals. *Remind me Friday to call Kim* still works: it now makes a one-time schedule that opens a chat on Friday. *Schedules* is one button in the Inbox's top bar. The deleted board can't be brought back.
  ```text
  Before                    After
  ------                    -----
  Opens on a week board     Opens on your chats
  "Remind me" adds a task   "Remind me" makes a schedule
  Tasks, backlog, goals     Gone
  Schedules as a tab        Schedules as a top button
  ```
- **What of yours stays.** All of Relay Everything stays as it is: the phone app, the website, the server, its tables and its own chat list. Nothing of Relay Everything uses the board's tables or the removed owner check, so none of it changes. The five shared files that Relay Everything changed keep their own lines and get the new lines too.
- **What is left out, and why.** No Relay Everything website page changes, because this update changes your app's Inbox and the assistant's tools, not the app, server, ring or connections that the website describes.
- **What you do yourself.** Nothing. Your board is empty today: no tasks this week, the four weeks before, or in the backlog. Just before the update goes live, the assistant reads the board again; if a task is there, it lists it and asks which to keep as a reminder.

## What the build needs

- **The WongStack source**: Ready, at version 51.0.0 on this computer.
- **App login to read the board**: Ready, the company app sign-in on this computer read the board on 2026-11-08.
- **Cloudflare and app keys**: Ready, in `.env`.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared Inbox and tools, not a Relay Everything behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 86 changed WongStack parts from the update check: 39 changed with no local edits, 9 new, 33 removed, 5 changed where this repo has its own edits. Lists are in the design.
- One new database step, `schema/migrations/20261107120000_inbox_chats.sql`: it adds the `chats` table and a `chat` column on `inbox_items`, and drops `tasks`, `week_goals` and `backlog_groups`. The publish applies it to staging and production by the normal data pipeline. Dropping the board's tables can't be undone.
- `app/worker/api/contract.ts` no longer exports `checkerOwns`; no mini app of this repo imports it.
- Non-goals: no Relay Everything feature change, no website page, no change to the `relay_*` tables.

## Decision log

- **2026-11-08** — Assumed: no open sync thread to close, because `memory.mjs search --type thread --tag sync` found none.
- **2026-11-08** — Assumed: keep the full drop step in the new migration, because only WongStack's own `20261028120000_task_board.sql` and the removed board code use `tasks`, `week_goals` or `backlog_groups`; every Relay Everything table is `relay_*`.
- **2026-11-08** — Assumed: no daily settings file needs its `tasks` entry removed, because this repo has no `.agents/daily/` folder.
- **2026-11-08** — Assumed: no mini app needs an owner-check change, because only WongStack's `employee-access` code uses `checkerOwns`, through `policy.ts`, not `contract.ts`.
- **2026-11-08** — Assumed: no reminder to make now, because `inbox.daily-tasks` for the weeks of 2026-10-19, 2026-10-26 and 2026-11-02 returned no tasks and an empty backlog; the build reads again just before publish.
- **2026-11-08** — Assumed: no spec delta (`skip_specs: true`), because no Relay Everything capability changes behavior.
- **2026-11-08** — Assumed: a sketch, not a prototype, for the Inbox, because the screen is WongStack's, already built and tested upstream; the build's staging preview shows the real one.
- **2026-11-08** — Assumed: no Relay Everything website page changes, because the update changes WongStack's Inbox and tools only.
- **2026-11-08** — Assumed: no other workspace overlaps this update, because the open plans change the phone app, photos and Home, not WongStack's Inbox files.
- **2026-11-08** — Check: `app/src/apps/inbox/Reviews.test.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/Drag.test.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/edits.test.ts` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/Groups.test.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/plan.test.ts` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/Rows.test.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/week.test.kit.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/src/apps/inbox/week/Week.test.tsx` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/worker/apps/inbox/tasks/daily-routes.test.ts` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/worker/apps/inbox/tasks/week-routes.test.ts` is deleted with the week board code it tested, because WongStack 51.0.0 deletes the board; the new Chats, Archive and chats tests cover the Inbox now.
- **2026-11-08** — Check: `app/.oxlintrc.json` drops its allowance for `src/lib/board.ts`, because that file is gone; the lint rule is now stricter, not looser.
- **2026-11-08** — Assumed: no reminder to make, because the board read just before publish (weeks of 2026-10-12 to 2026-11-09) found no tasks and an empty backlog.
- **2026-11-08** — Save checkpoint: built (39 files copied, 9 added, 33 deleted, 5 merged by hand), reviewed with no findings, merge check clean, preflight now current, app tests pass; the board was empty before publish.
