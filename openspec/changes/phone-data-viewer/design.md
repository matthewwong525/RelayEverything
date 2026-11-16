# Design: phone data viewer

## Context

The phone's Health and Location folder pages (`HealthPage`, `LocationPage` in `mobile/lib/screens/folder.dart`) show one switch and `sentLine`: *Sent 14:05 · 3 waiting*. The server already sums a day in `daySummary` (`app/worker/apps/relay/queries.ts`): health totals by `healthBuckets`, places as stays (or each place once on an older day), trips, and calendar events. The web page reads it through `GET summary`, and the AI connector's `day_summary` reads the same function. A phone key may read only `connections`, `notes`, `attachment` and `audio` (`PHONE_READS` in `caller.ts`).

The person chose: phone first, no map, and only aggregate data that reached Relay Everything's cloud: no copy on the phone, and nothing shown when the data does not go to the cloud.

## Goals / Non-Goals

**Goals:** a *Health data* and a *Places data* page on the phone, one day at a time, read from the person's space; the sync card says what still waits; a phone key reads no more than a day's totals.

**Non-Goals:** a map; a web page change; calendar or photos viewers; single readings or points; any copy on the phone; any change to what a round sends; sleep nights and workout details (the workspace *Health nights and workouts for the AI*).

## Decisions

### A new `GET day` route, not `GET summary` for phones

`day.ts` defines `relay.day`: the same `day` and `offset` input as `summary`, answered by `daySummary` minus `events` and `notes`, wrapped in `asPersonOrPhone`. `caller.ts` adds `day` to `PHONE_READS`. `summary` stays session-only and keeps its shape, so the web page does not change.

*Alternative:* let a phone key read `GET summary`. Rejected: it carries the day's calendar titles and people, which the viewer does not show, and a lost phone key should give away as little as it can.

*Alternative:* a phone-only shape with less health. Rejected: the person wants to see what the AI reads, which is `daySummary`'s totals.

### The phone asks once per day picked, and keeps nothing

`Api.day(date, offset)` in `mobile/lib/data/api.dart` sends the phone's local day and its UTC offset in minutes, as the web page's `today()` does. Each page holds the answer for the day shown in widget state only; leaving the page drops it. Both pages call the same route; each shows its own half.

### When the row shows

`See your data` shows only while all three hold: `settings.sending`, the notes place is Relay Everything (`settings.place == SendPlace.server`), and private data goes there too (`settings.privatePlace == SendPlace.server`); plus the folder's own switch (`settings.health` or `settings.history`). Otherwise the row is absent, with no text about it.

### The sync card

It reuses `sentLine(relay.healthSent, 'reading', now)` or `sentLine(relay.pointsSent, 'point', now)`, and one muted line: *This is what Relay Everything has, and what your AI reads.*, or, with uploads waiting, *N uploads are still on this phone and not shown yet.*

### Days

The page opens on today. ‹ goes back a day with no limit; › stops at today. The title row reads *Today*, *Yesterday*, then the weekday and date. A stay that crosses midnight shows with the times the server gives for that day.

### Errors

A failed or refused answer shows *Can't reach Relay Everything.* with *Try again*, and nothing from an earlier answer. A 401 or 403 shows the same and does not sign the phone out: sign-out stays the Account page's job.

## UX

### Use-case brief
A person who turned on Health or Location history wants to check that it reaches Relay Everything and look back at a day. Common case: open the folder, tap *See your data*, glance at today, step back a day or two. Edge cases: no signal; a day with nothing; uploads still waiting. A few times a week at most.

### Flow
Home → *Health* (or *Location*) → *See your data* → today. ‹ › change the day. Back goes to the folder.

### Hierarchy
The day's totals or stays are the content. The day row sits above them and the sync card under the title, both quieter. There are no buttons besides ‹ › and *Try again*. Only *Now* uses the accent: the one bright thing.

### Review
[review.html](review.html). The proposal's What Changes sketches *Health data* and *Places data*. A Flutter screen cannot run in the web prototype, so the plan shows sketches.

### Components
The folder page's `_FolderPage` shape (`SliverAppBar.large`, `BackTo`), `Group` cards, `ListTile` rows, `CupertinoIcons.chevron_back`/`chevron_forward` for ‹ ›, and `sentLine` for the sync card. New: a small `DayPicker` row shared by both pages.

## Risks / Trade-offs

- **A lost phone key now reads day totals and stays** → only one day per call, only totals and named stays, never readings, points or events; *Turn off* on the web page stops the key as before. The website's device-key and Privacy pages say so.
- **No signal means no view** → the person chose cloud-only; the card says what waits.
- **The iPhone simulator has no health data** → the device check covers *Places data* against staging data; health shows its empty state there and is checked on a real iPhone.

## Migration Plan

No data change. Phones on an older app never call `GET day`. Rolling back the server leaves the new app's pages showing *Can't reach Relay Everything.*
