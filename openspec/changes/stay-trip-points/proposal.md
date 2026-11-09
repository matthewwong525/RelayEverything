# Your AI can look into a stay or a trip, point by point

**Status:** ready-to-ship
**Branch:** frank-goat
**Open questions:** none

## Why

Your AI can tell you that you drove 42 km to Hamilton, but not which road you took or where you stopped on the way. It sees each stay and trip only as a summary. The points that make them are on the server, but no AI read and no API route gives them, so only a webhook gets them today.

## What Changes

- **Each stay and trip gets an id.** The places read and the day summary give each stay and each trip a number, as notes and photos have. Every field they give today stays the same.
  | A made-up Saturday | Today | After |
  |---|---|---|
  | Stay at Home, 08:00 to 10:12 | name, street, times | the same, and `id: 812` |
  | Trip, driving, 42 km, 38 min | mode, km, minutes | the same, and `id: 813` |
  | Stay at Bayfront Park, 10:50 to 12:30 | name, street, times | the same, and `id: 814` |

- **A new read gives the points of one stay or trip.** Your AI sends the id, and gets that stay's or trip's points from its start to its end: for a trip, its route. It gets only the points of the phone that made that stay or trip, even when two phones send. A stay you are still in reads to now. Each point has its time, where it was, how sure the phone was of it, and its street when it has one.
  ```mermaid
  sequenceDiagram
    participant You
    participant AI
    participant R as Relay
    You->>AI: Which way did I drive to Hamilton?
    AI->>R: places, Saturday
    R-->>AI: trip 813, driving, 42 km
    AI->>R: points of 813
    R-->>AI: 380 points, Gardiner to QEW
    AI-->>You: By the QEW, with a stop at Oakville
  ```

- **Or the points from one time to another.** For days before your phone made stays, the read also takes a start and an end time, up to 7 days, and gives every phone's points in that time.
  ```mermaid
  flowchart LR
    A["id of a stay or trip"] --> P["points"]
    B["from and to, up to 7 days"] --> P
  ```

- **A long trip still gives one short answer.** One read gives at most 500 points, spread evenly over the stay or trip, always with its first and last point. It also says how many points there were in all, so your AI knows when it sees fewer.
  | A made-up trip | Points kept | Answer |
  |---|---|---|
  | Walk to the shop, 12 min | 40 | all 40 |
  | Drive to Hamilton, 38 min | 380 | all 380 |
  | Drive to Montréal, 5 h 40 min | 3,120 | 500, about one in six, `total: 3120` |

- **With *Only stays and trips*, there are no points to give.** The read gives no points and says so, as the server keeps none. Nothing on the phone changes.

- **Your scripts get the same read.** The web API gets one new route that gives the same answer, and the website's pages say how to use it.
  | Page | What it adds |
  |---|---|
  | Connect your AI | The new *points* read, and the id on each stay and trip |
  | Connect a service | The new route |
  | Location | Your AI can look at a stay's or trip's points, unless you pick *Only stays and trips* |
  | API reference | The new route and the `id` fields |

Non-goals: no change to the phone app or your Relay Everything page; no map; no new data kept and nothing worked out again; no heart rate during a workout or a night (later); a phone key reads no points.

## What the build needs

- **Nothing.** The points and the stays are already on the server; no key, login or new table.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-places-timeline`: each stay and trip in the AI and API answers has an id, and a new read gives the location points of one stay or trip, by its id, or of a time range, at most 500 spread evenly with the total.

## Impact

- Server: `app/worker/apps/relay/queries.ts` (`id` on `Visit` and `Trip` from `staysIn`, day summary places keep it; new `stayPoints` and `rangePoints`); `app/worker/relay-mcp/inputs.ts` (the `points` tool), `answers.ts` (its answer), `api.ts` (`GET /v1/points`), `tools.ts` (count and server instructions); `openapi.ts` from the routes; `npm run relay:api-doc` writes `site/public/api/v1.openapi.json` and `site/src/content/docs/api/v1-reference.md`.
- Tests: `queries.test.ts`, `tools.test.ts`, `api.test.ts`, `openapi.test.ts`; `app/tests/relay-space-rows.sql` gains points inside its stay and trip.
- Docs: `site/src/content/docs/connections/connect-your-ai.md`, `api/connect-a-service.md`, `app/location.md`; `wiki/stack/relay-ai-connector.md`.
- No migration: `UNIQUE (device_id, at)` on `relay_locations` already gives the index the read needs.

## Decision log

- **2026-11-09** — Asked (in the planning chat) how to split the larger request → chose a small separate plan for this read: server and AI reads only, no phone change, no redo; heart rate during workouts and nights later.
- **2026-11-09** — Asked how the AI says which stay or trip it wants → chose by its id, or by a from and to time for days with points but no stays.
- **2026-11-09** — Asked what one read gives for a long trip → chose at most 500 points, spread evenly, with the first and last point and the total.
- **2026-11-09** — Assumed: the id is the `relay_stays` row id, because the phone's resend updates the row in place (`ON CONFLICT … DO UPDATE` in `stays.ts`), so an ongoing stay keeps its id as it grows.
- **2026-11-09** — Assumed: a read by time is at most 7 days, refused past that, because 500 points over more days says little and the count still reads every point.
- **2026-11-09** — Assumed: a read by time gives every phone's points together, with no device, because no answer holds a device id, and a stay's id already picks one phone.
- **2026-11-09** — Assumed: an ongoing stay or trip reads to now, not to its sent end, because points can arrive before the next stay update.
- **2026-11-09** — Assumed: the tool is named `points` and the route `GET /v1/points`, beside `places`, because it reads points, of a stay, a trip or a time.
- **2026-11-09** — Assumed: no phone key reach, because the phone data viewer plan gives a phone key no points, so a lost phone gives away little.
- **2026-11-09** — Assumed: no overlap in intent with *Take the ring out of everything people read* or *Your sleep as nights and your workouts*; both touch `tools.ts`, `inputs.ts` and the tool count, so the one that lands second updates the count.
- **2026-11-09** — Assumed (build): each part's test step ran once at the end, after all source and tests were written.
- **2026-11-09** — Assumed (build): a stay or trip still going reads to the later of now and its sent end, so a phone clock ahead of the server never cuts it short.
- **2026-11-09** — Assumed (build): a read by time may be 7 days and one hour, so a week with a clock change still counts as 7 days.
- **2026-11-09** — Assumed (build): the site page's own day summary route (`summary.ts`) gives the `id` too, as its answer check is strict and it reads the same `daySummary`; the page shows nothing new.
- **2026-11-09** — Built and reviewed inside `/ship`: the second look found nothing to fix; the change's 77 tests pass locally, while the full local suite timed out only on unrelated tests on a loaded machine (load about 28), so CI is the gate for 4.1. Task 4.2 runs on staging after this save.
