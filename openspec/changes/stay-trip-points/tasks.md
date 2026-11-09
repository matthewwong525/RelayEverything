# Tasks

## 1. Server reads

- [x] 1.1 In `app/worker/apps/relay/queries.ts`, add `id` to `StayRow`, to the `SELECT` in `staysIn`, and to `Visit` and `Trip` from stays (`visitOf`, the trip mapping); `dayPlaces` keeps it on a stay's place and street runs have none. Update the `placeVisits` and `daySummary` expectations in `queries.test.ts` and `tools.test.ts`, and add a test that a resent ongoing stay keeps its id. Verify: `npx vitest run worker/apps/relay/queries.test.ts` in `app/`.
- [x] 1.2 In `queries.ts`, add `MAX_POINTS = 500`, `stayPoints(db, id)` and `rangePoints(db, from, to)` as `design.md` says: one statement each that thins to at most 500 with the first and the last, and the total; a stay or trip by id reads only its own device, to now while `going`. Add tests in `queries.test.ts`: all points under 500; 3,120 points give 500 with both ends and `total` 3,120; a second device's points in the same time are left out; an ongoing stay reads past its sent end; an unknown id gives `null`; no points gives `total` 0. Verify: the same command.
- [x] 1.3 In `app/tests/relay-space-rows.sql`, add made-up points inside the Saturday stays and the drive, and one from the iPad during the café stay, so the connector tests read a real route and the two-phone case.

## 2. AI tool and web API

- [x] 2.1 In `app/worker/relay-mcp/inputs.ts`, add the `points` tool (`id`, or `from` and `to`, `timezone`) with a description that says a stay's or trip's id comes from `places` or `day_summary`, at most 500 points spread evenly with `total`, and that none means the person keeps no points; add the `id` to the `places` and `day_summary` descriptions.
- [x] 2.2 In `answers.ts`, answer `points`: refuse neither or both inputs and a range over 7 days (400), an unknown id (404); show times with `local()`; leave out a null `place`. In `tools.ts`, name the read in the header comment and the server instructions. Add `tools.test.ts` cases: a trip's route by id, a range, the iPad's point left out of a stay by id, each refusal, the tool listed read-only; change the tool counts in `tools.test.ts` and `auth.test.ts` to thirteen. Verify: `npx vitest run worker/relay-mcp` in `app/`.
- [x] 2.3 In `api.ts`, add `GET /v1/points` (`listPoints`) after `/v1/places`; add `api.test.ts` cases for `?id=` as text turned to a number, a range, and a 404 problem; run `npm run relay:api-doc` in `app/` so `site/public/api/v1.openapi.json` and `site/src/content/docs/api/v1-reference.md` gain the route and the `id` fields. Verify: `npx vitest run worker/relay-mcp/api.test.ts worker/relay-mcp/openapi.test.ts worker/apps/relay/api-doc.test.ts`.

## 3. Docs

- [x] 3.1 Website: in `site/src/content/docs/connections/connect-your-ai.md`, thirteen tools, twelve that read, the new **points** line, and the id on places and day_summary; in `api/connect-a-service.md`, the `GET /v1/points` line; in `app/location.md` under *Stays and trips* and *What to send*, that your AI can look at a stay's or trip's points, and that *Only stays and trips* leaves none. Verify: `node scripts/product-name.test.mjs` and the site build.
- [x] 3.2 Wiki: in `wiki/stack/relay-ai-connector.md`, thirteen tools, the **points** line (its two inputs, 500 and `total`, one device by id), and `id` on `places` and `day_summary`. Verify: the wiki link check passes.

## 4. Checks

- [ ] 4.1 Run `npm test` in `app/` and `node scripts/public-check.mjs`; fix what fails.
- [ ] 4.2 After `/save`, on staging, deploy the connector from `app/` with `npx wrangler deploy -c wrangler.relay-mcp.jsonc --env staging`, then with an API key call `GET /v1/places` for a day with stays, and `GET /v1/points?id=<a trip's id>`: the points run from the trip's start to its end, and `total` matches the count.
