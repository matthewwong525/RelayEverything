# Tasks

## 1. The import script

- [x] 1.1 In `scripts/import-wongstack-memory.test.mjs`, make `sourceStore().facts` throw `D1_ERROR: too many SQL variables` when a query has more than 100 `ids`, and add a test that a source with facts on both sides of a 5,000-number gap gives all of them; verify `node --test scripts/import-wongstack-memory.test.mjs` fails on today's code with that error
- [x] 1.2 In `scripts/import-wongstack-memory.mjs`, split `CHUNK` into `READ = 90` (used by `readFacts`) and `SEND = 200` (used by `chunks` and its comment), and replace `EMPTY_RANGES` with `EMPTY_NUMBERS = 10_000` read as `Math.ceil(EMPTY_NUMBERS / READ)` empty ranges; verify `node --test scripts/import-wongstack-memory.test.mjs` passes
- [x] 1.3 In `wiki/stack/relay-knowledge-web.md`, *Move a WongStack memory in*, add to *It only reads the source* that it reads 90 numbers a request, below the 100 a D1 store takes; verify the line reads in plain words and its links resolve

- [x] 1.4 Add `../scripts/import-wongstack-memory.test.mjs` to the `node --test` list in `app/package.json`'s `test` script, so CI runs it; verify `node --test ../scripts/import-wongstack-memory.test.mjs` from `app/` passes

## 2. Checks

- [x] 2.1 From `app/`, run `npm test` and verify it passes
