## Context

The deploy of PR #77 (main `fe36e36`) failed at its first step, `wrangler deploy -c wrangler.spaces.jsonc`: Cloudflare answered *Uncaught TypeError: (intermediate value).glob is not a function* ([the run](https://github.com/matthewwong525/RelayEverything/actions/runs/42564930465)). Wrangler bundles `app/worker/spaces-worker.ts` alone, with no Vite, so `import.meta.glob` is not there.

The runtime chain: `spaces-worker.ts → webhooks/log.ts → kinds.ts → webhooks/format.ts → stays.ts → api/contract.ts → apps/index.ts` (`import.meta.glob`). PR #77 added the `format.ts → stays.ts` import, for `STAY_SOURCES` and `TRIP_MODES`. `store.ts → api/contract.ts` is `import type` only, so the bundle drops it.

## Goals / Non-Goals

**Goals:** the spaces Worker starts with the stays and trips change; a check fails before merge when it loads route code again.

**Non-Goals:** no change to any message, route or schema; no revert of PR #77; no change to how the deploy runs.

## Decisions

- **Move the lists to `relay/store.ts`.** It already exports the shared zod shapes that `stays.ts` reads (`latitude`, `longitude`, `placeName`, `time`), and loads no route at run time. A new file for two lists is more code for no gain.
- **The guard is a test in `spaces-worker.test.ts`,** a copy of the line Worker's walker in `line-worker.test.ts`, with one difference: it skips `import type` lines, since they leave no code. It asserts that the walk reaches `webhooks/format.ts` (so the walk is real), and that no reached file is `api/contract.ts` or holds `import.meta.glob`. On a failure it prints the chain of files, so the reader sees which import to cut.
- **No shared walker module.** Two tests with a 10-line walker each is less to read than a helper and its import; a third copy would earn a helper.

## Risks / Trade-offs

- A regex walker misses a dynamic `import()` → none of the Worker code uses one today; the test reads static imports, as the line guard does.
- A mixed import such as `import { MINUTE, type Db }` still counts → right: it loads `MINUTE` at run time.
