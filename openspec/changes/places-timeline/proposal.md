# Your places as stays and trips, like Google Maps Timeline

**Status:** in-progress
**Branch:** naughty-spider
**Open questions:** none

## Why

Today your location history is a list of street names. A drive becomes many short "visits", one per street. A stop at a café shows the street, not the café. A trip says nothing about how you went or how far. Your AI gets the same list, so it can not answer "where did I go on Saturday?" well.

## What Changes

- **Your phone turns your points into stays and trips.** A stay is a time you were in one spot, inside about 100 m, for 5 minutes or more. The time between two stays is a trip. A drive is one trip, not twenty streets. A night at home with no new points is one stay. The phone keeps only the stay or trip in progress; when it ends, the phone sends it, with its points unless you chose otherwise, and keeps none of them. This starts from the update: days you already sent keep their street list. The rules follow Dawarich, the open-source Google Timeline app: we use its ideas, not its code.
  | A made-up Saturday | Today | After |
  |---|---|---|
  | 07:00 to 09:00 at home | 12 Maple Street | 12 Maple Street, 07:00 to 09:00 |
  | 09:00 to 09:15, by car | Elm Road, Oak Avenue, Bay Road, Lake Drive, and 9 more streets | Drive, 6.2 km, 15 min |
  | 09:15 to 10:20 at a café | Lake Drive | Corner Café, Lake Drive, 09:15 to 10:20 |
  | 10:20 to 10:40, on foot | Lake Drive, Park Lane | Walk, 1.4 km, 20 min |
  | 10:40 to 11:30 at the dentist | Park Lane | Smile Dental (your calendar), 10:40 to 11:30 |

- **Each trip says how you went, how far, and how long.** The phone's motion sensors tell walking, running, cycling, driving and still, on iPhone and Android. Without them, the phone guesses from your speed. A trip with too few points to tell says *unknown*. The distance adds up each step between points, so it is never longer than the real trip.
  | The phone knows | Mode |
  |---|---|
  | Motion: walking, running, cycling, in a vehicle | Walk, Run, Cycle, Drive |
  | No motion, speed under 8 km/h | Walk |
  | No motion, 8 to 25 km/h | Cycle |
  | No motion, 25 to 250 km/h | Drive |
  | Over 250 km/h | Fly |
  | Over 60 min with no point on the way | Unknown |

- **Each stay gets the best name the phone can find.** First your calendar: an event with a place, at that time, near the stay, such as *Smile Dental*. Then, on iPhone, Apple Maps' nearest place within 50 m, such as *Corner Café*, asked only when the phone knows where it is to within 50 m. Then the street. Then the coordinates. A stop on a road never gets a shop's name. The phone asks once per stay, not once per point, and only while sending is on, as the street lookup does today. Android has no shop names: its free lookup gives streets only, and Google's place search costs money.
  ```mermaid
  flowchart TD
    C["1. Your calendar"] --> M["2. Apple Maps, within 50 m"]
    M --> S["3. The street"]
    S --> X["4. The coordinates"]
  ```

- **Turning on *Location history* asks one more thing.** The iPhone asks for *Motion & Fitness*, and Android for *Physical activity*. Say no, and the phone guesses the mode from speed. The app reads only what kind of moving you did, never your steps here: those stay with Health. No real picture: the phone shows its own system question, which the plan's copy of the app can't show.
  ```screen
  <div class="card col gap phone">
    <b>"Relay Everything" would like to access your Motion &amp; Fitness Activity</b>
    <span class="muted">To tell a walk from a drive in your location history.</span>
    <div class="row gap"><button class="btn-ghost grow">Don't Allow</button><button class="btn-ghost grow">OK</button></div>
  </div>
  ```

- **You choose what to send, in the Location folder.** Under *What to send*: *Stays, trips and points* (the default), *Only stays and trips*, or *Only points*. *Only stays and trips* sends where you stayed and how you moved, not each point on the way; the phone still uses the points to work them out, then drops them. *Only points* sends the points as today, with street names, and asks for no motion. Switching to *Only stays and trips* drops the points that still wait on the phone. No real picture: the phone app is Flutter, which the plan's copy of the app can't run.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Home</button></div>
    <h3>Location</h3>
    <div class="card col gap"><div class="row gap"><span class="grow">Location history</span><span class="tag">On</span></div><span class="muted">Sent 14:05</span></div>
    <span class="muted">How often</span>
    <div class="card col gap"><div class="row gap"><span class="grow">Save battery</span><span class="tag">✓</span></div><span class="sep"/><div class="row gap"><span class="grow">Every 100 m</span></div></div>
    <span class="muted">What to send</span>
    <div class="card col gap">
      <div class="row gap"><div class="col grow"><span>Stays, trips and points</span><span class="muted">Where you stayed, how you moved, and each point on the way.</span></div><span class="tag">✓</span></div>
      <span class="sep"/>
      <div class="row gap"><div class="col grow"><span>Only stays and trips</span><span class="muted">Where you stayed and how you moved. No point on the way leaves the phone.</span></div></div>
      <span class="sep"/>
      <div class="row gap"><div class="col grow"><span>Only points</span><span class="muted">Each point, with its street, as before.</span></div></div>
    </div>
  </div>
  ```

- **Stays and trips go where your points go.** Signed in, they go to Relay Everything, and on to each webhook you ticked for *Location history*. Sending to your own webhook instead, they go straight there. Your own database gets them as a new message beside the points.
  ```mermaid
  flowchart TD
    P["Phone: stays, trips, points"] --> R["Relay Everything"]
    P -->|"own webhook"| W["Your webhook"]
    R -->|"ticked for Location"| W
  ```

- **Your AI answers with stays and trips.** The AI's *places* tool and its day summary give each stay with its name, street and times, and each trip with its mode, distance and time. A question such as "where did I go on Saturday?" gets one short, correct answer. Days from before the update answer as today. The AI still only reads.
  ```mermaid
  sequenceDiagram
    participant You
    participant AI
    participant R as Relay
    You->>AI: Where was I Saturday?
    AI->>R: day summary
    R-->>AI: 3 stays, 2 trips
    AI-->>You: Home, drive, Corner Café, walk
  ```

- **Your page's *Places today* list shows stays.** It looks the same, but each row is a stay with its real name and times, not one row per street. A timeline page on the web and the phone comes later, in its own plan. No real picture: the list's look does not change, only its rows, and the plan's copy of the page has no location history to show.
  ```screen
  <div class="card col gap">
    <h3>Places today</h3>
    <div class="card col gap">
      <div class="row gap"><span class="grow">12 Maple Street</span><span class="muted">07:00 to 09:00</span></div>
      <div class="row gap"><span class="grow">Corner Café</span><span class="muted">09:15 to 10:20</span></div>
      <div class="row gap"><span class="grow">Smile Dental</span><span class="muted">10:40 to 11:30</span></div>
    </div>
  </div>
  ```

- **The website says how it works.** The pages update in the same change:
  | Page | What it adds |
  |---|---|
  | Location | Stays, trips and modes, the motion question, how a stay gets its name, *What to send*, from the update on |
  | Connect your AI | What *places* and *day_summary* now give |
  | Privacy | The phone works out stays itself; Apple Maps and the street lookup get one stay's coordinates, only with sending on; motion stays on the phone |
  | Your own database | The new stays message |
  | API reference | The new stay and trip fields |

Non-goals: no names of your own (Home, Work, Gym) yet; no timeline page yet; no Google Maps Timeline import; no stays for days sent before the update; no Wi-Fi network use beyond the phone's own fix; no shop names on Android.

## What the build needs

- **Nothing.** Apple Maps' place search and both motion sensors need no key, and no new Apple capability: only the permission words in the app.

## Capabilities

### New Capabilities

- `relay-places-timeline`: the phone turns location points into stays and trips, with motion and speed for the mode and calendar, Apple Maps and street lookups for the name; sends them where its points go; the server keeps them, sends them to webhooks ticked for Location, and gives them to the AI connector, the `/v1/` API and the page.

### Modified Capabilities

None.

## Impact

- Phone, pure: `mobile/lib/sync/stays.dart` (new): the stay and trip rules over points and motion, no I/O; `stays_test.dart`.
- Phone, settings and screen: `settings.dart` (`locationSend`: `all`, `stays`, `points`; old settings read `all`), `relay.dart` and the controller (`setLocationSend`), `screens/folder.dart` (*What to send* on the Location page).
- Phone, data: `store.dart` (schema version up: `track` and `motions` tables for the open stay or trip; a `stays` outbox route), `outbox.dart`/`api.dart` (`POST stays`), `webhook.dart` (`location.stays`).
- Phone, rounds: `background.dart` and `controller.dart` run the timeline step after the points; `sync/location.dart` names a stay (street) and `sync/native.dart` (venue, motion history on iPhone; drained transitions on Android); `sync/calendar.dart` gives events at a time.
- iPhone: `RelayBackground.swift` (both ends of a `CLVisit`; `venue` through `MKLocalPointsOfInterestRequest`; `motion` through `CMMotionActivityManager.queryActivityStarting`); `Info.plist` `NSMotionUsageDescription`.
- Android: a Kotlin `ActivityReceiver` for the Activity Recognition Transition API writing to a file the round drains; `ACTIVITY_RECOGNITION` in `AndroidManifest.xml`; `play-services-location` in `android/app/build.gradle` if geolocator does not already bring it.
- Server: `schema/space-migrations/0013_stays.sql` (`relay_stays`, and `relay_outbox` rebuilt with the `stay` kind); `app/worker/apps/relay/stays.ts` (`POST stays`, upsert by device and start); `kinds.ts` (`location.stays` under *Location history*); `webhooks/format.ts`; `queries.ts` (`placeVisits` and `daySummary` read stays, else the old street runs); `api.ts`; `relay-mcp/answers.ts`, `openapi.ts`, `inputs.ts`; `app/src/apps/relay/read.ts`; `npm run relay:api-doc`.
- Docs: `site/src/content/docs/app/location.md`, `connections/connect-your-ai.md`, `connections/your-database.md`, `privacy.md`; `site/public/webhooks/receiver.mjs`; `wiki/relay-phone-sync.md`, `wiki/relay-space-migrations.md`, `wiki/stack/relay-ai-connector.md`.

## Decision log

- **2026-11-09** — Asked which parts to include → chose stays and trips with better AI answers, shop names on iPhone, and names of your own; not the Google Timeline import.
- **2026-11-09** — Asked where you see the timeline and rename a place → chose no page for now; later, the web page and the phone both.
- **2026-11-09** — Asked whether the AI may name places → chose no, it only reads.
- **2026-11-09** — Asked how to give a place your own name with no page → chose no own names for now, only better-named location data that a later timeline can show. This takes back *names of your own* from the first answer.
- **2026-11-09** — Asked (by Matthew's message) to see how Dawarich does it → read its visit detection, place naming and travel mode code; took its 100 m, 5 minute and 15 minute merge rules, its same-place silence rule, its never-a-venue-on-a-road rule, and its speed bands. Dawarich is AGPL-3.0 and Relay Everything is MIT, so the build copies no code, only the ideas.
- **2026-11-09** — Asked where stays and trips are worked out → chose on the phone, not on the server. This replaces the first draft, which worked them out on the server on each read.
- **2026-11-09** — Asked how to make names more accurate → chose your calendar and skipping bad fixes; asked in the same answer for Wi-Fi and motion sensors.
- **2026-11-09** — Asked where to use motion sensors → chose iPhone and Android now.
- **2026-11-09** — Asked whether a stay uses the joined Wi-Fi network → chose no: the phone's own fix already mixes in Wi-Fi, so no new Apple capability.
- **2026-11-09** — Asked where stays and trips go → chose where the points go: Relay Everything and its ticked webhooks, or the person's own webhook.
- **2026-11-09** — Asked what happens to history already sent → chose leave old days as they are, so the rules live once, on the phone.
- **2026-11-09** — Assumed: the phone keeps only the open stay or trip's points and motion, and drops them when it closes, because AGENTS.md promises the phone keeps no history; sending off drops them at once.
- **2026-11-09** — Assumed: the phone sends the stay you are at now when it opens and again when it closes, upserted by device and start, because the AI should know where you are now; a resend with nothing new wakes no webhook, as the calendar does.
- **2026-11-09** — Assumed: one name lookup per stay, not per point, so the per-point `venue` field of the first draft goes, because a stay is what gets a name and Apple throttles map searches.
- **2026-11-09** — Assumed: a calendar event names a stay only when the event overlaps the stay and its place, looked up once, is within 150 m, because an online meeting at home must not rename home; it applies only while *Calendar* is on.
- **2026-11-09** — Assumed: stays and trips go under the *Location history* webhook tick as a new `location.stays` message, not a new tick, because they are the same data, grouped.
- **2026-11-09** — Assumed: the *places* answer keeps `visits` (now stays, with more fields) and adds `trips`, and the day summary keeps `places` (one row per stay) and adds `trips`, because an app on the `/v1/` API keeps working.
- **2026-11-09** — Assumed: the page's *Places today* list keeps its look and shows stays, with no trip rows, because Matthew asked for no timeline page now.
- **2026-11-09** — Assumed: no new note type and no own-names table, because neither is in scope now.
- **2026-11-09** — Assumed: no new rows in `schema/seed.sql`, because location data lives in each person's space, not in the seeded database; the tests build their own made-up days, with made-up streets.
- **2026-11-09** — Assumed: overlap with *Send health, places, calendar and photos only to your own webhook* (in its own workspace, being built) is in files, not intent: stays follow the points' private place, and whichever lands second routes `stays` with `locations` in its merge.
- **2026-11-09** — Asked (by Matthew's note) to choose in the Location settings whether to send stays and trips or just the raw points → added *What to send* to the Location folder: *Stays, trips and points* (default), *Only stays and trips*, *Only points*.
- **2026-11-09** — Assumed: *Only stays and trips* drops the points waiting on the phone when picked, because a person who picks it for privacy expects no more points to leave; points already sent stay on the server.
- **2026-11-09** — Assumed: *Only points* skips the timeline step and the motion question, because nothing would use them; it behaves as today.
- **2026-11-09** — Assumed: the choice is on both phones and also applies in own-webhook mode, because it is about what leaves the phone, not where it goes.
- **2026-11-09** — Assumed: `relay_stays` has an `updated_at` column, so the change log gives a changed stay its own time, not the time it first came.
- **2026-11-09** — Assumed: every visit in the *places* answer gets `minutes`, the old street runs too, so each visit has the same fields.
- **2026-11-09** — Assumed: a trip's `from` and `to` are the nearest stays before and after it, and `null` when that stay is out of the range read.
- **2026-11-09** — Assumed: the made-up Saturday of stays and trips that the connector tests read goes in `app/tests/relay-space-rows.sql`, beside the other made-up space rows.
- **2026-11-09** — Assumed: the phone keeps the open stay or trip under the state key `stays.timeline`, not `timeline`, because the app deletes `timeline` at each open, where older versions kept the server's timeline.
- **2026-11-09** — Assumed: Android's motion changes go to `relay-motion.jsonl` and Dart reads and empties the file at each round, with no drain call on the `relay/motion` channel, because the round also runs from the background task, where no activity channel is open; the app asks for the changes again at each open, as Android forgets them after a restart.
- **2026-11-09** — Assumed: motion names a trip's mode only when moving covers at least half of the trip, because a short walk to the car must not make a drive a walk.
- **2026-11-09** — Assumed: a stay that goes before it has a name carries its coordinates as its name, with `source: point`, because the server needs a name; it gets its real name when it is sent again with its end.
- **2026-11-09** — Assumed: a trip with no time between two stays, as when the phone was off for a flight, is `unknown`, because there is no speed to tell its mode.
- **2026-11-09** — Assumed: a stay that merges with the last one goes again as ongoing, with the last stay's start, so the server and a webhook keep one stay.
- **2026-11-09** — Assumed: on iPhone, a visit's two points also go as points, and the store keeps a repeated time once, because iOS sends a visit's arrival first and the whole visit later.
- **2026-11-09** — Assumed: the old street runs fill any time in a read range that no stay or trip covers, not only time before the space's first stay, because a phone on *Only points*, or an old phone, would otherwise show nothing after the first stay; a point inside a stay or trip ends a run. The open trip's points show as streets until the trip goes, the price of the simple rule.
- **2026-11-09** — Assumed: with sending on, *Location history* off or *Only points* picked queues the open stay closed, its end the later of its last point and the end already sent, before the phone drops it; and the server reads a stay as ongoing only while its `end_at` or `updated_at` is within 6 hours, else as ended at `end_at`, because otherwise a stay stays ongoing forever when the phone stops sending it.
- **2026-11-09** — Assumed: each round, the phone sends the open stay again when its end moved on (its newest point, or the round's time for a still stay with no new point and no sure move), and not when nothing moved, because an ongoing stay showed its 5-minute end as its real end; a ticked webhook gets each change once.
- **2026-11-09** — Checkpoint: built and reviewed twice (nine findings fixed); the local checks pass. Left: the iPhone and Android builds in CI, and the staging check (7.2).
