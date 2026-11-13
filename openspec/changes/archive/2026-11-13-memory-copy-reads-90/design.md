# Design

## Context

`scripts/import-wongstack-memory.mjs` uses one constant, `CHUNK = 200`, for two jobs: `readFacts` asks `source.facts([{ ids }])` for 200 numbers a range, and `chunks` sends 200 facts a `POST /v1/memory/import`. WongOS's store is D1, which allows at most 100 bound variables in one statement, so its `facts` query fails with `D1_ERROR: too many SQL variables`. The send side is fine: the space's import route takes up to 200 facts. `EMPTY_RANGES = 50` ends the read after 50 empty ranges, that is 10,000 empty numbers at 200 a range.

## Goals / Non-Goals

**Goals:** every read stays below D1's 100-variable limit; the send size and the stop reach over a gap stay as they are.

**Non-Goals:** no change to the server's import route, to the plugin's memory copy, or to the memory store's own `facts` query.

## Decisions

- **Two sizes.** `READ = 90` for `readFacts`, `SEND = 200` for `chunks`. 90 leaves room under 100 for any other variable the store binds in the same query. One shared size of 90 would also work, but it would send more than twice as many chunks for no gain.
- **The stop counts numbers, not ranges.** `EMPTY_NUMBERS = 10_000`; the read stops after `Math.ceil(EMPTY_NUMBERS / READ)` empty ranges in a row. Keeping `EMPTY_RANGES = 50` would cut the reach over a gap from 10,000 numbers to 4,500.
- **The test stand-in enforces the limit.** `sourceStore().facts` throws `D1_ERROR: too many SQL variables` when a query has more than 100 `ids`, as D1 does. The existing 450-fact run then fails on today's code and passes on the fix, with no new fixture.

## Risks / Trade-offs

- [A source with more than about 10,000 facts makes more read requests: 112 at 10,000 numbers, not 50] → The reads are small and local to the source; WongOS's run at 90 finished.
