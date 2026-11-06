# Update WongStack to 50.1.0

**Status:** ready-to-ship
**Branch:** sync-wongstack-upstream
**Open questions:** none

## Why

This repo runs WongStack 48.2.0. Six releases came out since then (48.3.0 to 50.1.0). They make the assistant connect your tools for you, put every schedule in the app, and make the live view the one place where you type a password or a card.

## What Changes

- **What you get.** Say *connect my tools*, or *connect my Notion*, and the assistant makes each key for you and saves it in your app, unseen. A tool you add in a chat works in seconds, with no publish. The Inbox gets a Schedules list again, with *Pause*, *Resume* and *Run now*. You can add your own password manager, such as 1Password, to the assistant's browser. The chat name now shows the step that runs now.
  ```mermaid
  flowchart TB
    A["connect my Notion"] --> B["Key made"]
    B --> C["Saved, unseen"]
    C --> D["Notion works"]
  ```
- **What changes in how you work.** You type a card, a code or a password on the real site, in the live view, then tap *Hand back*. The card form and the password page are gone. Saved passwords stop working: each site asks you to sign in once, in the live view, the next time it needs you. Sites that are signed in now stay signed in.
  ```text
  Before                After
  ------                -----
  Card form page        Live view of the real site
  Password page         Sign in once in the live view
  "I'm finished"        "Hand back"
  ```
- **What of yours stays.** All of Relay stays as it is: the ring, the phone app, the Relay pages, the website and the Relay parts of the app. The few shared files that Relay changed keep Relay's lines and get the new lines too. Your memory, your notes and your keys do not change.
- **What is left out, and why.** One stray file from WongStack (a Python cache file) is not copied, because it is made by a computer, not written. The other chat that plans a browser change from WongOS builds on top of this update after it is live, because you chose to update first.
- **What you do yourself.** After it is live, the assistant asks you once whether to delete the old file of saved passwords on this computer, because it keeps them as plain text. It deletes the file only if you say yes, and a delete can not be undone. It also checks for routines and schedules to move to the app; this repo has none today, so it expects to move nothing. To connect your tools, say *connect my tools* in any chat.

## What the build needs

- **Nothing.** The update source is on this computer, and the Cloudflare and app keys are in `.env`.

## Capabilities

### New Capabilities

### Modified Capabilities

None: this update changes WongStack's shared tools, not a Relay behavior in `openspec/specs/`. The change sets `skip_specs: true`.

## Impact

- 163 changed WongStack parts from the update check (111 changed, 26 new, 19 removed, 7 changed where Relay has its own edits). Details and lists are in the design.
- New app tables from two new migrations (tools added in a chat; schedule definitions). The publish applies them to staging and production by the normal data pipeline.
- `AGENTS.md`'s WongStack block changes three rule lines; the Relay block above it stays.
- Non-goals: no Relay feature change, no Relay website page, no change to the browser proxy plan in the other chat.

## Decision log

- **2026-11-06** — Asked how this update and the other chat's "Browser proxy from WongOS" plan fit together → chose update first; the proxy plan builds on top after this is live.
- **2026-11-06** — Assumed: do not copy `.claude/skills/browser/scripts/__pycache__/launch-config.cpython-314.pyc`, because it is a generated cache file that WongStack listed by mistake; Python makes it again when needed.
- **2026-11-06** — Assumed: no spec delta (`skip_specs: true`), because no Relay capability in `openspec/specs/` changes behavior.
- **2026-11-06** — Assumed: no Relay website page changes, because the update changes the assistant's tools, not Relay's app, server, ring or connections that the website describes.
- **2026-11-06** — Assumed: the 49.0.0 schedule move runs after publish and finds nothing, because this repo has no `schedules/` folder, no `.agents/daily/` settings and the schedule list is empty.
- **2026-11-06** — Assumed: ask about deleting `~/.wong-stack/logins.json` after publish, not before, because the 50.0.0 note says so and the file exists on this computer.
- **2026-11-06** — Assumed: move the two after-publish steps (the saved-passwords file question and the schedule move) from the tasks to the design's Migration Plan, because they can only run once the change is live, and the ship runs them then.
- **2026-11-06** — Assumed: keep the core's migration list line in `app/tests/employee-access/connections.ts` exactly as WongStack has it, and load Relay's three migrations in a second loop after it, because the line-by-line merge check then finds every upstream line, and Relay's migrations only add.
- **2026-11-06** — Assumed: add `connect` to `components.skills` in `.claude/.wong-stack.json`, after `daily` as in the source list, because the update installs that new skill; every other key stays.
- **2026-11-06** — Assumed: point `wiki/development/README.md`'s links from the removed private form and passwords pages to saved details, your password manager and the watch link, because Relay's hub linked to the removed pages.
- **2026-11-06** — Archive checkpoint: built (136 files copied, 19 removed, 7 merged by hand), reviewed with no findings, and archived for the ship.
