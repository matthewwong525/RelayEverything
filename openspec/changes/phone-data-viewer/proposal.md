# See your health and places data on the phone

**Status:** planned, waiting for review
**Branch:** health-location-data-viewer
**Open questions:** none

## Why

Today the phone's Health and Location pages say only *Sent 14:05 · 3 waiting*. You can't see what reached Relay Everything, which is what your AI reads, so you can't tell if syncing works. You also can't look back at where you went.

## What Changes

- **Health: see a day's totals from the cloud.** The Health page gets a *See your data* row. It opens *Health data* on today, with ‹ › to go to other days. It shows the day's totals as Relay Everything has them, the same totals your AI reads: steps, sleep, heart rate, workouts, and each other type that day has. The phone keeps no copy: it asks Relay Everything each time you open a day.
  ```screen
  <div class="card col gap phone">
    <span class="muted">‹ Health</span>
    <h3>Health data</h3>
    <div class="row gap"><span class="btn-ghost">‹</span><span class="grow">Today</span><span class="btn-ghost">›</span></div>
    <div class="card col">
      <span>Sent 14:05 · none waiting</span>
      <span class="muted">This is what Relay Everything has, and what your AI reads.</span>
    </div>
    <div class="card col gap">
      <div class="row gap"><span class="grow">Steps</span><span>8,412</span></div>
      <div class="row gap"><span class="grow">Sleep</span><span>7 h 12 min</span></div>
      <div class="row gap"><span class="grow">Heart rate</span><span>58–141 bpm, 74 on average</span></div>
      <div class="row gap"><span class="grow">Workouts</span><span>1 · 34 min</span></div>
      <div class="row gap"><span class="grow">Resting heart rate</span><span>56 bpm</span></div>
    </div>
  </div>
  ```

- **Places: see where you went on a day.** The Location page gets a *See your data* row. It opens *Places data* on today, with ‹ › for other days. It lists the day's stays and the trips between them in order, as Relay Everything has them: the place name and from when to when, and for a trip how you went, how far and how long. The stay you are at says *Now*. There is no map yet.
  ```screen
  <div class="card col gap phone">
    <span class="muted">‹ Location</span>
    <h3>Places data</h3>
    <div class="row gap"><span class="btn-ghost">‹</span><span class="grow">Today</span><span class="btn-ghost">›</span></div>
    <div class="card col">
      <span>Sent 14:05 · 2 waiting</span>
      <span class="muted">2 uploads are still on this phone and not shown yet.</span>
    </div>
    <div class="card col gap">
      <div class="row gap"><span class="grow">Home</span><span class="muted">00:00–08:40</span></div>
      <div class="row gap"><span class="grow muted">Walking · 1.2 km · 18 min</span></div>
      <div class="row gap"><span class="grow">Blue Bottle Coffee</span><span class="muted">09:00–09:45</span></div>
      <div class="row gap"><span class="grow muted">Driving · 6.4 km · 15 min</span></div>
      <div class="row gap"><span class="grow">Work</span><span class="muted">10:00–now</span><span class="tag">Now</span></div>
    </div>
  </div>
  ```

- **Only what reached Relay Everything shows.** The pages show only data in your Relay Everything space. What still waits on the phone shows only as the count in the top card. If you send health and places only to your own webhook, or you are signed out, there is no *See your data* row: your data is not in our cloud to show.
  ```mermaid
  flowchart TB
    A["Phone reads health and places"] --> B{"Sends to Relay Everything?"}
    B -->|Yes| C["See your data shows the day"]
    B -->|"Own webhook, or signed out"| D["No See your data row"]
  ```

- **The phone may read your day totals back.** Until now a phone's key could only send health and places, never read them. Now it can read one day's totals and stays and trips from its own person's space. It still reads no single reading, no point, no calendar event, no chat and no photo.

Non-goals: no map, no web page change, no calendar or photos viewer, no single readings or points, no copy kept on the phone, and no change to what is sent or where. Sleep as nights and workouts with their kind and distance are planned on their own, in *Health nights and workouts for the AI*.

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

- `relay-phone-data-viewer`: the phone's *Health data* and *Places data* pages: when they show, what they read from the person's space, and the sync card.

### Modified Capabilities

- `relay-device-keys`: a phone key also reads its person's day totals of health and its stays and trips for a day, and nothing finer.

## Impact

- Server: a new `GET day` route in `app/worker/apps/relay/` that answers `daySummary` without calendar events or the notes count, open to a session and a phone key (`asPersonOrPhone`); `caller.ts` adds `day` to `PHONE_READS`; `npm run relay:api-doc` regenerates the API page.
- Phone: `Api.day` in `mobile/lib/data/api.dart`; new `mobile/lib/screens/health_data.dart` and `places_data.dart`; a *See your data* row in `folder.dart`'s `HealthPage` and `LocationPage`.
- Docs: the device-key line in `AGENTS.md` and `wiki/relay-spaces.md`; the website's `health.md`, `location.md`, `privacy.md` and the device-key docs.
- No change to what a phone sends, to webhooks, or to storage.

## Decision log

- **2026-11-09** — Asked where the viewer goes first → chose the phone app.
- **2026-11-09** — Asked where map pictures come from → chose no map yet: a data viewer only.
- **2026-11-09** — Asked where the phone viewer gets its data → the person asked whether the data is already on the phone; answered that health is (in Apple Health or Health Connect) and places are not.
- **2026-11-09** — Asked how far back → chose 7 days; later replaced by the cloud-only note below.
- **2026-11-09** — Asked (plan note) how the viewer should get its data → the person chose to show only aggregate insights once they sync with Relay Everything's cloud, with no 7-day copy on the phone, and nothing when data does not go to the cloud. The 7-day places copy, its table and the places-timeline and home-screen spec changes are dropped.
- **2026-11-09** — Asked whether health needs pre-processing on the phone for the AI, like places → chose a separate plan for sleep as nights and full workouts; opened as the workspace *Health nights and workouts for the AI*.
- **2026-11-09** — Assumed: ‹ › go to any earlier day, not only 7, because the cloud keeps every day and the 7-day limit came from the dropped phone copy.
- **2026-11-09** — Assumed: a phone key reads day totals and stays and trips only, through a new route without calendar events, because a lost phone key should give away as little as it can.
- **2026-11-09** — Assumed: with private data going to the person's own webhook, or signed out, the folder shows no *See your data* row and no line about it, because the person said not to show data that is not in the cloud.
- **2026-11-09** — Assumed: each page opens from a *See your data* row on its folder page, not a new Home row, because Home's rows already open these folders.
- **2026-11-09** — Assumed: saved the plan at close, unbuilt, because the person ran /close before reviewing it.
