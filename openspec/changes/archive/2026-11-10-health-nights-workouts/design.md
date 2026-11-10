# Design: nights and full workouts, made on the phone

## Context

See proposal.md, Why. `mobile/lib/sync/health.dart` maps each `HealthDataType` to a server type in `kinds`. On iPhone, `SLEEP_ASLEEP`, `SLEEP_LIGHT`, `SLEEP_DEEP` and `SLEEP_REM` all become `sleep`, a span whose value is its minutes; `SLEEP_AWAKE` and `SLEEP_IN_BED` are not read. On Android, `SLEEP_SESSION` becomes `sleep`. A `WORKOUT` becomes `workout`, its minutes only, though the package's `WorkoutHealthValue` holds `workoutActivityType`, `totalDistance` (m) and `totalEnergyBurned` (kcal).

`syncHealth` reads from `health.since` minus 2 hours. The package's iPhone read uses `predicateForSamples(..., options: .strictStartDate)`, so it gets only samples that start in the window. `HealthWake` in `RelayBackground.swift` wakes for heart rate each hour of the night, so `health.since` moves on through the night; the watch writes the night's stages at wake, starting hours before. So the start of a night can fall before the window and is never read (inferred from the code, not seen on a device).

The server keeps samples in `relay_health`, once per `(device_id, type, start_at, end_at, source)`; `queries.ts` sums them per day. Stays and trips (`openspec/specs/relay-places-timeline/spec.md`) are the model: the phone makes the grouped rows, a route upserts them, and a message under the data's webhook tick sends them on.

## Goals / Non-Goals

**Goals:** one night per sleep and source, with its times and stage minutes, made on the phone; each workout with its kind, distance and calories; no night lost to a late write; the last 90 days redone once; nights and workout details to the server, its Health webhooks, the person's own webhook, the AI connector and the API; every field each answer had stays.

**Non-goals:** a screen on the web page or phone; a sleep score; heart rate per night; workout routes; nights made on the server from old `sleep` rows.

## Decisions

### One pure module on the phone

`mobile/lib/sync/nights.dart`: `nightsOf(List<SleepReading> readings, {required DateTime from})` → `List<Night>`. No I/O, so `nights_test.dart` drives it with made-up readings. A `SleepReading` is `{source, stage, start, end}`; the round turns each sleep `HealthDataPoint` into one.

Stages, from the package's types:

| iPhone | Android | Stage |
|---|---|---|
| `SLEEP_IN_BED` | `SLEEP_SESSION` | `in_bed` (the night's span only, never minutes asleep) |
| `SLEEP_ASLEEP` | `SLEEP_ASLEEP` | `asleep` (asleep, no stage known) |
| `SLEEP_LIGHT` | `SLEEP_LIGHT` | `core` |
| `SLEEP_DEEP` | `SLEEP_DEEP` | `deep` |
| `SLEEP_REM` | `SLEEP_REM` | `rem` |
| `SLEEP_AWAKE` | `SLEEP_AWAKE`, `SLEEP_AWAKE_IN_BED`, `SLEEP_OUT_OF_BED` | `awake` |

The rules, constants at the top of the file:

| Constant | Value | Rule |
|---|---|---|
| `gap` | 2 h | Per source, by start: a reading that starts within 2 hours of the open night's end joins it; else it starts a new night. |
| `edge` | 2 h | A night whose first reading starts within 2 hours of the read's `from` may be cut: it is not made, as the read that covered its start made it. |

A night: `start` (first reading's start), `end` (last reading's end), `asleepAt` (first asleep-kind reading's start, else null), `wokeAt` (last asleep-kind reading's end, else null), and minutes `asleep`, `core`, `deep`, `rem`, `awake`. Asleep-kind is `asleep`, `core`, `deep`, `rem`; `asleep` minutes are their sum. Readings of one source can overlap (a stage inside `in_bed`): stage minutes are each stage's union of spans, so an overlap never counts twice. An Android session with no stages has `asleep` = its span minus `awake`, and `asleepAt`/`wokeAt` at its ends, as today's `sleep` sample counts it. A night with no asleep-kind and no session (only `in_bed` from an iPhone's bedtime) still goes, with `asleep: 0`: it gives the bedtime.

A night also has `stages`: its timeline, a list of `{ stage, start, end }` in time order, from the `asleep`, `core`, `deep`, `rem` and `awake` readings (never `in_bed`, which is the night's span). Where two readings overlap, the later one starts where the earlier ends; touching steps of the same stage join. At most 400 steps (a watch night has about 50): a night with more keeps its first 400. The stage minutes come from the readings, as above, so a cut timeline never changes them. An Android session with no stages, or a bedtime-only night, has an empty list.

*Alternative:* each raw `sleep` sample gains its stage, and awake and in-bed go as samples too. That breaks the day's sleep total for older servers and receivers, which would count awake time as sleep; a timeline inside the night changes nothing they read.

*Alternative:* the server groups stage samples into nights at each read. Matthew chose the phone: the person's own webhook then gets whole nights, and only the phone knows how its platform shapes sleep.

### What the phone reads and sends

`kinds` keeps today's map for samples: the same types still go as `sleep`, so the day total does not move. A second map, `nightStages`, holds the types read for nights only (`SLEEP_IN_BED`, `SLEEP_AWAKE` on iPhone; the Android stages). `askedTypes` covers both, so a phone asks once at the next open, as for new types today. On Android, `allow()` also asks for `DISTANCE_DELTA` and `TOTAL_CALORIES_BURNED`, which the package reads inside each workout and which are never sent as samples; the manifest gains `READ_DISTANCE` and `READ_TOTAL_CALORIES_BURNED`.

A `workout` sample gains three optional fields: `kind` (the `HealthWorkoutActivityType` name in lower case, such as `running`, `traditional_strength_training`), `distance` (m) and `calories` (kcal), each left out when the phone has none.

### The 36-hour read and the sent list

Each round reads in two parts: every type except sleep and workouts from `health.since` minus 2 hours, as today; sleep, night stages and workouts from `health.since` minus 36 hours. The second part makes nights with `from` at its start, and queues the `sleep` and `workout` samples and the nights.

The state key `health.sent` holds a JSON map, key → hash, for the nights (`night <source> <start>`) and the `sleep` and `workout` samples (their sample key) queued in the last 48 hours. A row whose key and hash are there is not queued again; keys older than 48 hours go. The map is saved in the same transaction as the queue, as `calendar_sent` is. Turning health or sending off empties it.

### The 90-day redo

The state key `health.detail` is a second backfill mark, for sleep, night stages and workouts only. A phone that has `health.since` and no `health.detail` sets it to the newer of `health.backfill` (if any) and now. While it is newer than 90 days ago, each round reads the 7 days before it, plus `edge` more, and moves it back. Nights from the edge part are left out by the `edge` rule, so a night across two weeks is made once, by the newer read. The server skips `sleep` samples it has, adds the ones it missed, and fills workout details. `startHealth` sets `health.detail` to now, so a new phone's first backfill already carries details.

### Server

`schema/space-migrations/0014_nights.sql`:

```sql
CREATE TABLE relay_nights (
  id INTEGER PRIMARY KEY, device_id TEXT NOT NULL REFERENCES relay_devices(id), source TEXT NOT NULL,
  start_at INTEGER NOT NULL, end_at INTEGER NOT NULL, asleep_at INTEGER, woke_at INTEGER,
  asleep REAL NOT NULL, core REAL NOT NULL, deep REAL NOT NULL, rem REAL NOT NULL, awake REAL NOT NULL,
  stages TEXT NOT NULL DEFAULT '[]', updated_at INTEGER NOT NULL, created_at INTEGER NOT NULL, UNIQUE (device_id, source, start_at));
CREATE INDEX relay_nights_end ON relay_nights(end_at);
ALTER TABLE relay_health ADD COLUMN kind TEXT;
ALTER TABLE relay_health ADD COLUMN distance REAL;
ALTER TABLE relay_health ADD COLUMN calories REAL;
```

plus `relay_outbox` rebuilt with the `night` kind and its triggers, as `0013` rebuilt it, and an `AFTER UPDATE OF kind ON relay_health` trigger that logs `health` for the row, so a workout whose details fill goes to webhooks again.

- `POST nights` (`nights.ts`, `asDevice`, at most `BATCH`) upserts by `(device_id, source, start_at)` and changes a row only when a field differs, as `POST stays` does. `REACH.phone` gains `nights`.
- `POST health`: the sample schema takes `kind` (≤ 60 chars), `distance` and `calories` (0 to 1e6) only on `workout`. The insert's `ON CONFLICT` becomes `DO UPDATE SET kind, distance, calories = excluded… WHERE relay_health.kind IS NULL AND excluded.kind IS NOT NULL`, so a resend fills an old workout once and changes nothing after. `added` counts only new rows, as today; a filled row wakes the webhooks too.
- `kinds.ts`: *Health* gains log kind `night` and message `health.nights`; `webhooks/format.ts` gains its shape and the three workout fields on `health.samples`; the phone's own-webhook mode sends the same from `webhook.dart`. *Your own database* gets a `###` heading and `receiver.mjs` a branch.

### Reads

`nightPage(db, from, to, limit)` reads nights whose `end_at` is in the range, newest first. Of nights that overlap, it keeps the one with the most `asleep` minutes. `workoutPage(db, from, to, limit)` reads `workout` rows by start, newest first, with the device's and source's duplicates of one workout (same start within a minute) kept once.

- New read-only tool *nights* and `GET /v1/nights`: `{ nights: [{ start, end, asleepAt, wokeAt, minutes: { asleep, core, deep, rem, awake }, source, device, stages? }], next }`. The input `stages` (default false) adds each night's timeline, so a month of nights stays a short answer and a look into one night gets the detail.
- New read-only tool *workouts* and `GET /v1/workouts`: `{ workouts: [{ kind, start, end, minutes, km, calories, source, device }], next }`, `kind` `null` for a workout from before.
- *day_summary* and `GET /v1/days/{day}`: adds `nights` (each night or nap that ended in the day, by the overlap rule) and `workouts.items` (the day's workouts as above); `sleepMinutes` and `workouts.count`/`minutes` stay.
- `kinds.ts`'s *Health* lists the new routes and tools. Times go through `local()`. `npm run relay:api-doc` rewrites the API pages.

## Risks / Trade-offs

- [A new phone sends `POST nights` to a server without the route, which answers 404] → the hosted server goes live with the merge, before the phone build reaches TestFlight; the outbox keeps the rows and retries.
- [An old server refuses a `workout` sample with the new fields, as its schema is strict, and the whole batch fails] → same order: the server first; a self-hosted server updates with the repository. Until then, the batch waits on the phone, not lost.
- [Reading 36 hours of sleep each hour costs a wake's time] → a night is about 50 readings; the sent list keeps the upload small.
- [Android's package reads distance and calories with a separate call per workout] → a week of the redo is a handful of workouts; a refused permission leaves the fields out.
- [iPhone's `HKWorkout.totalDistance` and `totalEnergyBurned` are deprecated in iOS 18] → they still answer; a later package update can move to workout statistics.
- [Android calories include the resting burn; iPhone's do not] → the Health page says so; one field, not two, because only one of them exists on each phone.
- [Two sources write one night] → each is kept; reads give the one with the most sleep.

## Migration Plan

`0014_nights` adds a table, three nullable columns and the outbox kind; no row moves. Old phones send neither nights nor details, and their days read as today. An updated phone redoes 90 days of sleep and workouts once.
