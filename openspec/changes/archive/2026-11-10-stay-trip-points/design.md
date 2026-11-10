# Design

## Context

`relay_stays` (migration `0013_stays.sql`) holds the phone's stays and trips, one row per `(device_id, kind, start_at)`; `stays.ts` upserts on that key, so a resent ongoing stay keeps its row `id`. `relay_locations` holds the raw points, `UNIQUE (device_id, at)`, which gives an index on `(device_id, at)`, plus `relay_locations_at`. Nothing links the two but device and time.

`staysIn` in `app/worker/apps/relay/queries.ts` reads stays and trips for `placeVisits` (the `places` tool, `fetch`'s `placesNearby`) and `dayPlaces` (`day_summary`). It drops the row id today. `streetRuns` and `dayPlaces` make places from uncovered points; those have no row and get no id.

The connector's tools and `/v1/` routes share one input per tool (`inputs.ts`) and one answer (`answers.ts`); `openapi.ts` and `npm run relay:api-doc` describe `ROUTES`.

## Goals / Non-Goals

**Goals:**
- An `id` on each stay and trip that comes from `relay_stays`, in `places`, `fetch` and `day_summary`, and the routes behind them.
- One read-only tool, `points`, and one route, `GET /v1/points`, that answer the points of a stay or trip by id, or of a range up to 7 days, at most 500, with `total`.

**Non-Goals:**
- No phone, page, migration, webhook or phone-key change. No map. No heart rate per workout or night.

## Decisions

### The id is the row id

`StayRow` gains `id`; `visitOf` and the trip mapping in `staysIn` put it first. `dayPlaces` keeps it on a stay's place (`...id`), and the uncovered rows have none. The JSON key is `id`, a number, as photos and notes use `id`. Alternative: a made-up text id from device and start. Rejected: it would carry the device id out, which no answer may.

### One tool with two inputs

`TOOLS.points` takes `id` (`z.number().int().positive()`), or `from` and `to`, and `timezone`. Zod keeps both optional; the answer refuses neither, both, or a range over 7 days (`Refusal`, 400), and an unknown id (`Refusal`, 404, "No stay or trip has this id."). `api.ts`'s `numbers()` already turns `id` from text into a number for `GET`. Alternative: two tools. Rejected: the AI picks the wrong one more often than it fills the wrong field.

### Reads in queries.ts

```text
stayPoints(db, id)          -> { kind, start, end, total, points } | null
rangePoints(db, from, to)   -> { total, points }
```

- `stayPoints` reads the row `SELECT id, device_id, kind, start_at, end_at, ongoing, updated_at FROM relay_stays WHERE id = ?`. Its end is `Date.now()` when `going(row)` (sent as ongoing within `STALE`), else `end_at`. The points are `device_id = ? AND at >= start AND at <= end`.
- `rangePoints` reads `at >= from AND at < to` over every device.
- Both thin in one statement, so no more than `MAX_POINTS = 500` rows leave D1:

```sql
WITH p AS (SELECT at, lat, lon, accuracy, place, ROW_NUMBER() OVER (ORDER BY at, id) AS n, COUNT(*) OVER () AS total
           FROM relay_locations WHERE ...)
SELECT at, lat, lon, accuracy, place, total FROM p
WHERE total <= ?max OR n = 1 OR (n - 1) * (?max - 1) / (total - 1) > (n - 2) * (?max - 1) / (total - 1)
ORDER BY at, n
```

  Integer division keeps the first row of each of `max - 1` equal steps, and the last row (`n = total`) always passes, so the answer has at most `max` rows with the first and the last. A test checks 3,120 points give 500 with both ends. The check in `tools.test.ts` that `queries.ts` writes nothing still passes.

- A point's `place` is left out when null, as `address` is on a stay.

### The answer

```json
{ "id": 813, "kind": "trip", "from": "2026-11-07T10:12:00-05:00", "to": "2026-11-07T10:50:00-05:00", "timezone": "America/Toronto",
  "total": 380, "points": [{ "at": "2026-11-07T10:12:04-05:00", "lat": 43.65, "lon": -79.38, "accuracy": 12, "place": "Maple St" }] }
```

By range, `id` and `kind` are absent. Times go through `local()`, as every other answer. `total: 0` with `points: []` is a normal answer, not a refusal: the person may have picked *Only stays and trips*. The tool's description says so, so the AI does not retry.

### The route

`ROUTES` gains `{ method: "GET", path: "/v1/points", id: "listPoints", summary: TOOLS.points.title, tools: ["points"], description: TOOLS.points.description }`, after `/v1/places`. `openapi.ts` reads it; `npm run relay:api-doc` writes the website's OpenAPI file and reference page.

### Words

The `places` and `day_summary` descriptions add that each stay and trip has an `id` for `points`. `tools.ts` comment and the MCP server instructions name the new read; the tool counts in `auth.test.ts`, `tools.test.ts`, the wiki and the website go from twelve to thirteen.

## Risks / Trade-offs

- **The count reads every point in the window.** A 7-day range at every 100 m is a few thousand rows: cheap for D1. The 7-day cap bounds it; a stay or trip has no cap, but one trip is rarely more than a day of points.
- **Ids are guessable within a space.** Each space is one person's, and every reader already reads all of it, so a guessed id reads only the person's own data.
- **Two other plans edit the same files.** *Take the ring out of everything people read* edits `tools.ts` and `inputs.ts` words; *Your sleep as nights and your workouts* adds two tools. Each is small; the one that lands second fixes the count and merges the lines.
- **A stay replaced by `longest`.** When two phones' stays overlap, the answer shows only the longer one's id. Its points are its own phone's, which is what the person saw in the summary.
