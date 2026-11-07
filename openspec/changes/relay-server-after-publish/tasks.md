# Tasks

## 1. Staging catch-up queue

- [x] 1.1 In `app/wrangler.spaces.jsonc` `env.staging`, set the `RELAY_WEBHOOKS` producer queue to `relay-everything-server-webhooks-staging`, with a comment on why; verify `npx wrangler deploy -c wrangler.spaces.jsonc --env staging --dry-run` lists that queue.
- [x] 1.2 Add `app/worker/queue-pairing.test.ts`: for each spaces environment, a Worker in the same environment consumes its producer queue and binds `SPACES`; verify it fails on the old staging value and passes on the new one.

## 2. After-publish server command

- [x] 2.1 Add `scripts/publish-relay-server.mjs` by design.md decision 3 (`--ref`, `--dry-run`, `--staging-only`, export, `npm ci`, staging spaces → connector → server, then live server, Worker-name check before each deploy, one `result=` line); verify `--help` prints usage.
- [x] 2.2 Add `scripts/publish-relay-server.test.mjs` with a fake runner: order of steps, `CLOUDFLARE_ENV` only for staging, stop and `result=failed step=` on a staging failure with no live deploy, refuse a redirect naming the wrong Worker, `--dry-run` deploys nothing; verify `node --test scripts/publish-relay-server.test.mjs` passes.
- [x] 2.3 Update `AGENTS.md` (after each publish, run both commands and report both `result=` lines) and `wiki/relay-spaces.md` (The Workers and their order: the command replaces the hand steps; staging wake-ups go to the server's queue); verify `node scripts/product-name.test.mjs` and the wiki checks pass.

## 3. Checks

- [ ] 3.1 Run `node scripts/publish-relay-server.mjs --ref HEAD --staging-only` and confirm `result=deployed`; then on app-staging.relayeverything.com, with a webhook whose receiver answers 503 past the queue's retries, confirm the space's next 15-minute wake-up sends the missed note (wrangler tail on `relay-everything-server-staging`).
- [ ] 3.2 Run `/save` and confirm CI is green, including the new tests.
