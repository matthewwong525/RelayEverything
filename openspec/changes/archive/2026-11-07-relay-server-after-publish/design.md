## Context

See proposal.md – Why. Four Workers matter here (wiki/relay-spaces.md, The Workers and their order): spaces, AI connector, shared server, company app. `scripts/cf-deploy.sh` on a publish deploys the live spaces Worker, the live connector and the live company app. Nothing deploys the shared server (live or staging), nor the staging spaces Worker or staging connector after a merge; branches deploy the staging spaces Worker by hand.

Queues today:

| Env | Spaces Worker produces to | Consumer | Has SPACES |
|---|---|---|---|
| live | `relay-everything-webhooks` | company app `relay-everything` | yes |
| staging | `relay-everything-webhooks-staging` | company app `relay-everything-staging` | **no** |
| staging | (server) `relay-everything-server-webhooks-staging` | `relay-everything-server-staging` | yes |

## Goals / Non-Goals

Goals: staging wake-ups consumed where spaces exist; one deterministic after-publish command for the server; a test that keeps the queue pairing true.

Non-goals: changing `cf-deploy.sh` or `deploy.yml` (shared WongStack files with a take-build guard that refuses routes); deploying the live spaces Worker or connector (CI already does).

## Decisions

1. **Point `env.staging` of `wrangler.spaces.jsonc` at `relay-everything-server-webhooks-staging`.** The staging shared server already consumes it with the same batch and retry settings. Alternative: give the company app's staging Worker `SPACES`: impossible, previews reach no other Worker's objects.
2. **A config test, `app/worker/queue-pairing.test.ts`.** It reads `wrangler.spaces.jsonc`, `wrangler.jsonc` and `wrangler.relay.jsonc` (with `stripJsonc`), and for each spaces environment (top level, `staging`, `local`) checks that some config's same environment consumes the producer queue and binds `SPACES`. Local maps to the company app's `local`, which binds SPACES. Deterministic, runs in `test.yml`.
3. **`scripts/publish-relay-server.mjs`, run from this computer after each publish, like `publish-relay-site.mjs`.** Alternative: a CI job. Refused because `--take-build` rejects a build that claims a route, the deploy token has no zone permission for the custom domains, and both are shared WongStack code. The command:
   - `--ref <commit>` (default `origin/main`), `--dry-run`, `--staging-only` (for a check, skips live).
   - Exports the ref with `git archive` into a temp folder (never the working checkout, so old `node_modules` can't break it), runs `npm ci` in `app/`.
   - Staging: `wrangler deploy -c wrangler.spaces.jsonc --env staging`, `wrangler deploy -c wrangler.relay-mcp.jsonc --env staging`, then `RELAY_CONFIG=wrangler.relay.jsonc CLOUDFLARE_ENV=staging npm run build:relay-only` and `wrangler deploy` (follows the build redirect).
   - Live: a fresh `RELAY_CONFIG=wrangler.relay.jsonc npm run build:relay-only` with no `CLOUDFLARE_ENV`, then `wrangler deploy`. Before it, check the redirect names `relay-everything-server`, and before each staging deploy that it names a `-staging` Worker, so a missed env never lands on live.
   - Stops at the first failure. Prints one `result=deployed ref=<sha> workers=...`, `result=failed step=<name>`, or `result=dry-run`.
   - The commands run through an injectable runner so the test checks order, env vars, stop-on-failure and the result line without Cloudflare.
4. **AGENTS.md's after-publish line names both commands**; `wiki/relay-spaces.md` replaces the hand steps with the command and drops "the staging spaces Worker stays stale" wording.

## Risks / Trade-offs

- [The command depends on someone running it after a publish] → It sits in the same AGENTS.md line /ship already follows for the website; one line to follow, not five hand steps.
- [Updating the staging spaces Worker from main drops a branch's hand-deployed space steps] → Already true between branches; the wiki tells a branch to redeploy.
- [The live shared server picks up a broken build] → Staging goes first with the same commit and must pass; CI gated the merge.
- [Staging D1 migrations for main] → Each branch's preview already applied them to the staging database before merge; the command applies none.

## Migration Plan

Merge, then run `node scripts/publish-relay-server.mjs` once. Rollback: `wrangler rollback` per Worker, or rerun with `--ref <earlier commit>`.
