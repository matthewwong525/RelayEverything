# Design: stays and trips, worked out on the phone

## Context

See proposal.md, Why. Each phone sends points to `POST locations` (`samples.ts`), stored in the space's `relay_locations`, once per `(device_id, at)`. `placeVisits` and `daySummary` in `queries.ts` group runs of the same street `place`. On iPhone, `PlacesWake` in `RelayBackground.swift` keeps points in `relay-points.jsonl` (*Save battery*: significant changes and `CLVisit`s; *Every 100 m*: a point each 100 m or 5 minutes), and `drainPoints` in `native.dart` moves them into the store's `points` table and names the newest 10 through `geocoding`. A departed `CLVisit` today adds one point, at its departure, so the arrival is lost. On Android, the controller listens to `PhonePlaces.history()`, a point each 100 m, under a foreground service. `queuePoints` moves waiting points to the outbox; nothing is kept after it is sent.

Dawarich (github.com/Freika/dawarich, AGPL-3.0) does this job on a server: a dwell sweep, a same-place gap bridger, a stay assembler, a place attributor that votes a POI before an address and never names a venue on a road, and speed profiles for the mode. We take its rules and numbers, never its code: this repository is MIT.

## Goals / Non-Goals

**Goals:** the phone closes stays and trips as points come, with motion for the mode on iPhone and Android; one name lookup per stay, calendar first; the phone keeps only the open stay or trip; stays go where the points go; the server stores them, sends them to Location webhooks, and answers the AI, the API and the page with them, keeping every field those answers had.

**Non-goals:** own names; a timeline page; Google Timeline import; stays for old days; reading the joined Wi-Fi network; shop names on Android.

## Decisions

### One pure module on the phone

`mobile/lib/sync/stays.dart` holds `TimelineState` (the open stay or trip: its points and motion) and `step(state, points, motions, now)` → `(closed segments, the open segment, the new state)`. No I/O, so `stays_test.dart` drives it with made-up days. The round feeds it new points and motion, sends what closed, saves the state, and drops what the state no longer needs.

*Alternative:* the server works out stays on each read (the first draft). Matthew chose the phone: the person's own webhook then gets stays too, and the server holds one more copy of nothing but the result. Old days stay as they are, so the rules live once.

### The rules (from Dawarich, with our numbers)

Constants at the top of `stays.dart`:

| Constant | Value | Rule |
|---|---|---|
| `radiusM` | 100 | A point joins the open stay when it is within 100 m of the stay's running center and within 150 m of its first point, so a slow walk can't drag the circle along. |
| `minStay` | 5 min | A cluster is a stay when it spans 5 minutes or more. |
| `still` | 30 min | A silence of 30 minutes or more after a point means the phone was still there, as *Save battery* sends only on a move of about 500 m: the point's cluster is a stay to the next point. |
| `merge` | 15 min | Two stays within 100 m with less than 15 minutes between them are one. |
| `poorFixM` | 250 | A point less sure than 250 m joins no stay; it still counts in a trip. |
| `goodFixM` | 50 | Apple Maps is asked only when the stay's median accuracy is within 50 m. |

A silence at the same place, of any length, is one stay. Motion sharpens the edges: a stay ends at the first motion change to walking, running, cycling or a vehicle after its last point, when the motion is sure (*high* on iPhone, an *enter* transition on Android), and a trip with motion *stationary* for 5 minutes inside 100 m splits around a stay. Only sure motion starts that stillness; any move, sure or not, ends it.

The open stay is sent when it reaches `minStay` with `ongoing: true`, again each round its end moves on (its newest point, or the round's time while the phone is still with no new point and no sure move), and again when it closes. A trip is sent when the stay after it opens. A late point (one the store marks because it came after a round stepped past its time, never one a round already stepped) at the last stay's place, after its last point and before the point that ended it, moves that stay's end and is sent again, while the trip after it is open.

### Trips

- `km`: each step from the first stay's center, through each trip point, to the next stay's center, summed and rounded to 0.1.
- `minutes`: from leaving to arriving.
- `mode`: the motion kind that covers most of the trip's time, when motion was allowed: `walking`, `running`, `cycling`, `driving` (a vehicle). Else, or with too little motion, the median speed of steps of 30 seconds or more, else `km` over `minutes`: under 8 km/h `walking`, 8 to 25 `cycling`, 25 to 250 `driving`, over 250 `flying` (motion has no flying, so speed over 250 always wins). A trip over 60 minutes with no point inside is `unknown`.

### A stay's name

Once per stay, when it opens (`minStay`), with sending on:

1. **Calendar**, while *Calendar* is on: an event that overlaps the stay and has a location that is not a link. Its location is looked up once (`geocoding`'s `locationFromAddress`, cached by text for the round); within 150 m of the stay, the stay takes `name` = the location's first comma part, or the event title when that part starts with a digit (a street address), and `event` = the title.
2. **Apple Maps**, iPhone only, when the stay's median accuracy is within `goodFixM`: the `venue` channel call, the nearest point of interest within 50 m.
3. **The street**: `PhonePlaces.nameOf` at the stay's center, as today's `placeOf`.
4. **The coordinates**, `43.651, -79.383`.

`address` is the street when the name came from 1 or 2. `source` says which: `calendar`, `map`, `street`, `point`. A failed lookup goes to the next step. Asks per round: at most 3 stays named; the rest wait, unnamed, for the next round, and are sent named when they close.

### Motion

- **iPhone**: the `relay/background` channel gains `motion(from, to)`: `CMMotionActivityManager.queryActivityStarting`, which reads the phone's last 7 days, so a wake reads what happened while closed. It answers `{ at, kind, sure }` changes. `Info.plist` gains `NSMotionUsageDescription`. The app asks when *Location history* turns on; a no leaves speed only.
- **Android**: a Kotlin `ActivityReceiver` gets Activity Recognition Transition API changes (enter and exit of `IN_VEHICLE`, `ON_BICYCLE`, `WALKING`, `RUNNING`, `STILL`) through a `PendingIntent`, so it works with the app closed, and appends each to `relay-motion.jsonl`; a `relay/motion` channel registers and unregisters it and drains the file. `ACTIVITY_RECOGNITION` is asked when *Location history* turns on (Android 10 and up); a no leaves speed only.

The store's `motions` table keeps changes from the open segment's start; older ones go when a segment closes.

### Phone store and rounds

Schema version up: `track` (the open segment's points, by `at`) and `motions`; a `timeline` state key holds the open segment's summary. The round order, in `backgroundRound` and the controller's drain:

1. Drain points (iPhone) or take the streamed ones (Android), as today, into `points` and `track`.
2. Drain motion.
3. `step`; name what needs a name; queue each closed or opened segment to the outbox route `stays`; drop `track` and `motions` rows before the open segment.
4. `queuePoints` (skipped for *Only stays and trips*) and flush, as today.

Turning *Location history* or sending off clears `track`, `motions` and the state, as it drops waiting points today. With sending on, *Location history* off or a change to *Only points* first queues the open stay closed, its end the later of its last point and the end already sent.

### What to send

`Settings.locationSend` (`LocationSend.all`, `stays`, `points`; saved as `locationSend`; old settings read `all`). It gates two steps of the round: `points` skips the timeline step and the motion ask, so the round is today's; `stays` runs the timeline step but never calls `queuePoints`, and drops each point from `points` once `track` has it. Picking `stays` deletes the `points` table's rows (not the outbox's, which is already on its way). The Location page reads and sets it through `Relay.setLocationSend`; switching from `points` to another asks for motion if it was never asked.

### On iPhone: both ends of a visit

A departed `CLVisit` adds two points at its coordinate, one at `arrivalDate` and one at `departureDate`; an arrived one adds one, at `arrivalDate`. The store and the server skip a repeated time. `venue` uses `MKLocalPointsOfInterestRequest` with a 50 m radius around the point (iOS 14; the app's lowest is 15.0).

### Server

`schema/space-migrations/0013_stays.sql`:

```sql
CREATE TABLE relay_stays (
  id INTEGER PRIMARY KEY, device_id TEXT NOT NULL REFERENCES relay_devices(id),
  kind TEXT NOT NULL CHECK (kind IN ('stay', 'trip')), start_at INTEGER NOT NULL, end_at INTEGER NOT NULL,
  ongoing INTEGER NOT NULL DEFAULT 0, lat REAL, lon REAL, name TEXT, address TEXT, event TEXT,
  source TEXT CHECK (source IN ('calendar', 'map', 'street', 'point')), mode TEXT, km REAL,
  created_at INTEGER NOT NULL, UNIQUE (device_id, kind, start_at));
```

plus its index on `start_at`, and `relay_outbox` rebuilt with the `stay` kind and its trigger, as `0012` rebuilt it. `POST stays` (`stays.ts`, `asDevice`, at most `BATCH`) upserts by `(device_id, kind, start_at)` and changes a row only when a field differs, as `POST calendar` does, so a resend logs nothing. `kinds.ts`: *Location history* gains log kind `stay` and message `location.stays`, with `webhooks/format.ts`'s shape, the public schema, a `###` heading on *Your own database*, and a branch in `receiver.mjs`. The phone's own-webhook mode sends the same message from `webhook.dart`; `REACH.phone` gains `stays`.

### Reads

`placeVisits(db, from, to, limit)` reads `relay_stays` overlapping the range: `visits` are the stays, `trips` the trips, ordered by start. Where two devices' stays overlap, the longer one is kept, and the read goes on until `limit + 1` stays remain or the rows end. Points that no stay or trip covers add the old street runs, so old days and a phone on *Only points* read as today. `daySummary` does the same for the day: `places` one row per stay, plus `trips`. A stay reads as `ongoing` only while its `end_at` or `updated_at` is within 6 hours; older, it ended at `end_at`.

- *places* and `GET /v1/places`: `{ visits, trips, next }`. A visit keeps `name`, `lat`, `lon`, `arrived`, `left`, and adds `address`, `event`, `minutes`, and `ongoing` when true. A trip is `{ left, arrived, mode, km, minutes, from, to }`, `from` and `to` the stays' names.
- *day_summary* and `GET /v1/days/{day}`: `places` as above, plus `trips`.
- *fetch*: `placesNearby` is the stays within 30 minutes of the note.

Times go through `local()`. The tool words in `inputs.ts` say *stays* and *trips*. `npm run relay:api-doc` rewrites the API pages.

## UX

The Location page gains a *What to send* group under *How often*, shown while *Location history* is on, on both phones: a `RadioGroup<LocationSend>` of three `RadioListTile`s with a subtitle each, as *How often* is built. The picked row's check is its only mark, so *New note* stays the one bright thing. Picking one applies at once, with no question; *Only stays and trips* says under the group that points still waiting were dropped.

Otherwise no new screen. Turning on *Location history* asks for motion after the location permission, on both phones; the Location folder is otherwise unchanged. A no is final until the person changes it in the phone's settings; the app does not ask again.

## Risks / Trade-offs

- [A new phone sends `POST stays` to a server without the route, which answers 404] → the hosted server goes live with the merge, before the phone build reaches TestFlight; a self-hosted server updates with the repository. The outbox keeps the rows and retries, so nothing is lost once the server updates.
- [The rules live in Dart, so a fix reaches only new days] → chosen: old days stay as they are. Tests pin each rule with made-up days.
- [A 30-minute silence while the phone was off becomes a stay where the person was not] → motion, when allowed, shows the move; with none, the stay ends at the next point, and an empty trip over 60 minutes is `unknown`.
- [Android's Transition API needs Google Play services] → without it, the receiver registers nothing and the mode comes from speed.
- [The nearest place within 50 m is a neighbour, in a mall] → only within 50 m and with a good fix; the calendar wins when it knows; own names, later, fix the rest.
- [An iPhone wake has about 25 seconds] → at most 3 stays named a round; points and segments are stored before any lookup, so a cut wake loses names, never data.
- [The private-data-to-own-webhook change edits `store.dart` and the background round in another workspace] → the `stays` route goes with `locations` to the private place; whichever lands second takes the other's lines in its merge.

## Migration Plan

`0013_stays` adds a table and rebuilds the outbox with one more kind; no row moves. Old phones never call `POST stays`, and their days read as today. A phone updating mid-stay starts its first segment at its next point.
