# Keep the Relay Everything server current after each publish, and let the test site catch up lost webhook sends

**Status:** ready-to-ship
**Branch:** `staging-webhook-catchup`
**Open questions:** none

## Why

A check of webhooks on 2026-11-07 found two gaps. On the test site, a webhook send that is lost is never sent again, because the 15-minute catch-up goes to a line that nothing on the test site reads. And nothing updates the Relay Everything server after a publish: the test site ran a morning build all day, and the live server waits for someone to remember a hand step.

## What Changes

- **The test site catches up lost sends.** Each person's space wakes every 15 minutes and asks for anything a webhook missed. On the test site, that wake-up now goes to the line the test server reads, as it already does on live. A check stops a future change from pointing it at a line no server reads.
  ```mermaid
  flowchart TD
    A["Space, every 15 min"] --> Q["Test server's line"]
    Q --> S["Missed items sent"]
    A -. "before" .-> X["Line nothing reads"]
  ```
- **One command after each publish updates the server, test site first, then live.** It takes the published version, updates the test site's three parts in order, then the live server, and prints one result line. If the test site fails, live is not touched. It runs after each publish, beside the website update, so no one has to remember it.
  ```mermaid
  flowchart TD
    P["Publish"] --> T["Test site: 3 parts"]
    T -- "ok" --> L["Live server"]
    T -- "fails" --> R["Stop; live unchanged"]
  ```

Non-goals: moving these updates into the cloud build (it can't claim the server's web address), and the other findings of the same check (note files to webhooks, iPhone signing), which have their own plans.

## What the build needs

- **Cloudflare login on this computer**: Ready. The hand update uses it today.

## Capabilities

### New Capabilities
- `relay-server-publish`: the shared server and its staging parts are updated from the published version after each publish, in order, with one result line; each environment's space catch-up wake-ups reach a Worker that holds the spaces.

### Modified Capabilities

## Impact

- `app/wrangler.spaces.jsonc` (`env.staging` producer queue → `relay-everything-server-webhooks-staging`).
- New `scripts/publish-relay-server.mjs` and its test; a new config test for the queue pairing.
- `AGENTS.md` publish line, `wiki/relay-spaces.md` (The Workers and their order), `.agents/skills/ship` if it lists the after-publish commands.
- Deploys: `relay-everything-spaces-staging`, `relay-everything-mcp-staging`, `relay-everything-server-staging`, `relay-everything-server` (live).

## Decision log

- **2026-11-07** — Asked whether the after-publish command should also update the live server → chose test and live.
- **2026-11-07** — Assumed: one plan for both gaps, because the person asked for it.
- **2026-11-07** — Assumed: run the command from this computer after each publish, like the website, not in the cloud build, because the cloud build refuses a build that claims a web address and its key has no zone access; the server claims `app.relayeverything.com`.
- **2026-11-07** — Assumed: the command updates all three test-site parts but only the live server, because each publish already updates the live spaces and AI connector.
- **2026-11-07** — Assumed: a publish's update of the test site's spaces Worker may drop a branch's hand-deployed space steps, because that already happens between branches and the wiki says to redeploy the branch.
- **2026-11-07** — Assumed: the command takes the Cloudflare key from this computer's `.env`, as `publish-relay-site.mjs` does, because this computer has no wrangler login and the hand update used that key.
- **2026-11-07** — Assumed: the command's test joins the `node --test` list in `app/package.json`, so CI runs it.
- **2026-11-07** — Check: `app/package.json` adds `../scripts/publish-relay-server.test.mjs` to the `node --test` list in `test`, because CI must run the new command's test; it loosens nothing.
- **2026-11-07** — Assumed: a `--ref` that git can't find prints `result=failed step=ref`, because the spec says every run prints one result line (from the second look).
- **2026-11-07** — Check: task 3.1's wake-up after a send that fails past every queue retry was not run; `--ref HEAD --staging-only` printed `result=deployed ref=8e37202`, and `wrangler queues info` shows `relay-everything-spaces-staging` producing to `relay-everything-server-webhooks-staging`, which only `relay-everything-server-staging` consumes. Exhausting the retries and waiting for the 15-minute alarm takes hours, so it is an open thread for `/verify`.
- **2026-11-07** — Archived for publish; spec relay-server-publish added to the main specs.
