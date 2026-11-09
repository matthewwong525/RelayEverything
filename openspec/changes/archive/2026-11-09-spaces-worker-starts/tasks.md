## 1. Code and test

- [x] 1.1 Move `STAY_SOURCES` and `TRIP_MODES` from `app/worker/apps/relay/stays.ts` to `app/worker/apps/relay/store.ts`; import them from `./store.ts` in `stays.ts` and from `../store.ts` in `webhooks/format.ts`.
- [x] 1.2 In `app/worker/spaces-worker.test.ts`, add the import-graph guard: walk static runtime imports from `spaces-worker.ts` (skip `import type`), assert the walk reaches `apps/relay/webhooks/format.ts`, and assert no reached file is `api/contract.ts` or holds `import.meta.glob`, printing the file chain on a failure.
- [x] 1.3 Add one line to *The Workers and their order* in `wiki/relay-spaces.md`: the spaces Worker is bundled alone, so it loads no route code and no `import.meta.glob`, and `spaces-worker.test.ts` checks it.

## 2. Checks

- [x] 2.1 Show the guard fails on the old import: with `format.ts` still importing from `../stays.ts`, the new test fails and names the chain; then with the fix it passes.
- [x] 2.2 Bundle the spaces Worker with no deploy: `npx wrangler deploy -c wrangler.spaces.jsonc --dry-run --outdir <tmp>` from `app/`, and confirm the bundle holds no `import.meta.glob` and no `.glob(` call.
- [x] 2.3 Run `npm test` in `app/`, and `node scripts/public-check.mjs` and `node scripts/product-name.test.mjs`.
