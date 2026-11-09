# Fix the deploy: the spaces Worker starts again

**Status:** ready-to-ship
**Branch:** spaces-worker-starts
**Open questions:** none

## Why

The publish of stays and trips did not go live. Its deploy stopped at the first step: Cloudflare would not start the new spaces Worker, the part that keeps each person's data. Live is unharmed: the deploy stopped before it changed anything, so people still use the version before stays and trips.

## What Changes

- **The spaces Worker starts again.** The webhook message for stays and trips needs the two lists of names: where a stay's name came from, and how a trip went. It took them from the `POST stays` route. That route also loads the web app's list of mini apps, which only the web app's build can make, so the spaces Worker stopped at its start. The two lists move to a file that loads no route, and both the route and the webhook message read them there. Nothing a person sees changes: the same names, the same messages.
  ```mermaid
  flowchart TD
    W["Spaces Worker"] --> F["Webhook message"]
    F -. "before" .-> R["Stays route"]
    R -.-> A["Mini-app list: fails"]
    F -- "after" --> S["Store file: two lists"]
  ```

- **A check stops it from coming back.** A new test walks every file that the spaces Worker loads. It fails, and names the file, when one of them loads the route code or anything that only the web app's build can make. The same check already guards the live line Worker.
  ```text
  ✗ the spaces Worker reaches no route code
    webhooks/format.ts
     → relay/stays.ts
     → api/contract.ts
  ```

- **Then stays and trips go live.** Once this fix is published, the deploy runs again with the stays and trips change and this fix together.

## What the build needs

- **Nothing.** The fix moves code and adds a test.

## Decision log

**2026-11-09** — Assumed: move `STAY_SOURCES` and `TRIP_MODES` into `relay/store.ts`, because it already holds the shared shapes that both routes and webhooks read (`placeName`, `time`), and its only `api/contract.ts` import is `import type`, which the bundle drops.

**2026-11-09** — Assumed: the new guard skips `import type` lines, because they leave no code in the bundle; the line Worker's walker reads them too, and so first made `store.ts` look like the cause.

**2026-11-09** — Assumed: no revert of the stays and trips change, because live is unharmed and a fix forward is one small move; `/ship`'s live-look repair builds a fix, not a revert.

**2026-11-09** — Asked whether to publish past the ship's red-main stop, since the only red check on `main` is the failed deploy this fix repairs → chose *Publish past it*. The ship's archive, release numbering and ready mark ran by hand; the save gate and merge ran as usual.

**2026-11-09** — Archive checkpoint: archived as `openspec/changes/archive/2026-11-09-spaces-worker-starts`, saved on branch `spaces-worker-starts` for the ship.

## Capabilities

### New Capabilities

### Modified Capabilities

- `relay-server-publish`: the spaces Worker loads only code that a plain Worker bundle can run, and a check fails when it does not.

## Impact

- `app/worker/apps/relay/store.ts`: gains `STAY_SOURCES` and `TRIP_MODES`.
- `app/worker/apps/relay/stays.ts`, `app/worker/apps/relay/webhooks/format.ts`: import the lists from `store.ts`.
- `app/worker/spaces-worker.test.ts`: the import-graph guard.
- `wiki/relay-spaces.md`: one line in *The Workers and their order* on what the spaces Worker may load.
