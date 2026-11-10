# Your sleep as nights and your workouts with their kind, distance and calories

**Status:** ready-to-ship
**Branch:** warm-leopard
**Open questions:** none

## Why

Today your phone sends sleep as loose minutes and a workout as its length only. Your AI can say "you slept 7 h 10 min" but not when you went to bed, when you woke, or how much was deep sleep. It can say "one workout, 40 min" but not that it was a 5 km run. An Apple Watch also writes the whole night when you wake, and the phone reads back only 2 hours, so it can miss the start of the night.

## What Changes

- **Your phone turns your sleep into nights.** A night has your bedtime, when you fell asleep, when you woke, and the minutes in each stage: core (light), deep, REM and awake. The phone groups its own sleep readings into nights, as it groups points into stays, so your AI, your webhooks and your own database all get whole nights. It still sends the sleep minutes it sends today, so the day's sleep total stays the same. A nap is a short night of its own. Each app or watch that tracks your sleep makes its own night; your AI gets the one with the most sleep.
  | A made-up night | Today | After |
  |---|---|---|
  | In bed | not sent | 23:05 |
  | Fell asleep | not sent | 23:20 |
  | Woke up | not sent | 06:55 |
  | Asleep | 7 h 10 min | 7 h 10 min: core 4 h 05, deep 1 h 15, REM 1 h 50 |
  | Awake in the night | not sent | 25 min |
  | When each stage came | not sent | 23:20 core, 00:10 deep, 01:05 REM, 01:30 core, ... |

- **Each night keeps its stage timeline, so you can look into it.** Besides the totals, a night carries each stage in order, with its times: about 50 short steps a night. So your AI can answer "when was my deep sleep?" or "how often did I wake?", not only "how much". The timeline goes everywhere the night goes, your own webhook too. A night from a source with no stages, such as a phone's bedtime, has none.
  ```mermaid
  flowchart LR
    A["23:20 core"] --> B["00:10 deep"]
    B --> C["01:05 REM"]
    C --> D["02:30 awake"]
  ```

- **Each workout keeps its kind, distance and calories.** Today a workout goes as its minutes. After, it also goes with what you did, how far, and the calories it used, when the phone has them. On Android, the calories are all the calories burned in the workout's time; on iPhone, only the active calories, as Apple Health shows them.
  | A made-up workout | Today | After |
  |---|---|---|
  | 07:10 to 07:42 | Workout, 32 min | Run, 32 min, 5.1 km, 410 kcal |
  | 18:00 to 18:45 | Workout, 45 min | Strength training, 45 min, 260 kcal |

- **A night your watch writes late is not lost.** Each round, the phone reads sleep and workouts again from the last 36 hours, not 2, because a watch writes the whole night when you wake. Nights and workouts that did not change do not go again.
  ```mermaid
  sequenceDiagram
    participant W as Watch
    participant P as Phone
    participant R as Relay
    P->>R: 03:00 round, heart rate
    W->>P: 07:00 the whole night, 23:05 to 06:55
    P->>P: 07:10 round reads back 36 h
    P->>R: one night, all of it
  ```

- **Your last 90 days get nights and workout kinds once.** After the update, the phone reads your sleep and workouts again, one week each round, newest first, and sends them as nights and full workouts. Workouts already sent get their kind, distance and calories. Sleep that the phone missed before is filled in. Sleep and workouts are few readings, so this takes about 13 rounds and does not slow the rest.
  ```mermaid
  flowchart LR
    U["Update"] --> W1["This week"]
    W1 --> W2["The week before"]
    W2 --> D["... 90 days"]
  ```

- **Android asks once more, for distance and calories.** On Android, the next open shows Health Connect's question for *Distance* and *Total calories burned*, as it does when new types come. Say no, and workouts go with their kind and minutes only. An iPhone asks nothing new: sleep stages and a workout's distance and calories come with what you already allowed. No real picture: the phone shows its own system question, which the plan's copy of the app can't show.
  ```screen
  <div class="card col gap phone">
    <b>Allow Relay Everything to access Health Connect?</b>
    <span class="muted">Relay Everything wants to read:</span>
    <div class="row gap"><span class="grow">Distance</span><span class="tag">On</span></div>
    <div class="row gap"><span class="grow">Total calories burned</span><span class="tag">On</span></div>
    <div class="row gap"><button class="btn-ghost grow">Cancel</button><button class="btn-ghost grow">Allow</button></div>
  </div>
  ```

- **Nights and workouts go where your health goes.** Signed in, they go to Relay Everything and on to each webhook you ticked for *Health*. With *Only my own webhook*, or sending to your own webhook instead, they go straight there. Your own database gets nights as a new message, and workouts as today's health message with three more fields.
  ```mermaid
  flowchart TD
    P["Phone: nights, workouts"] --> R["Relay Everything"]
    P -->|"own webhook"| W["Your webhook"]
    R -->|"ticked for Health"| W
  ```

- **Your AI answers with nights and workouts.** The day summary gives the night that ended that morning, and any nap, and each workout of the day. Two new reads give nights and workouts over any time, and the nights read gives each night's stage timeline when the AI asks for it, so "how did I sleep this week?" and "how far did I run in October?" get one short, correct answer. The AI still only reads.
  ```mermaid
  sequenceDiagram
    participant You
    participant AI
    participant R as Relay
    You->>AI: How did I sleep this week?
    AI->>R: nights, last 7 days
    R-->>AI: 7 nights with stages
    AI-->>You: Bed near 23:10, 7 h 05 average, deep lowest on Thursday
  ```

- **The website says how it works.** The pages update in the same change:
  | Page | What it adds |
  |---|---|
  | Health | Nights, their stages and stage timeline, workouts with kind, distance and calories, the 36-hour read, the 90-day redo, Android's new question, Android's calories |
  | Connect your AI | The new *nights* and *workouts* reads, and what the day summary adds |
  | Privacy | Health now includes sleep stages and each workout's kind, distance and calories |
  | Your own database | The new nights message and the workout fields |
  | API reference | The new nights and workouts routes and fields |

Non-goals: no change to your Relay Everything web page or the phone's screens (the phone data viewer can show nights later); no sleep score; no heart rate per night or per workout yet (the server can work it out later from readings it has); no read of the points behind a stay or trip (its own plan, in its own workspace); no workout route maps; no nights worked out on the server from old sleep minutes.

## What the build needs

- **Nothing.** The health package the phone already uses gives sleep stages and a workout's kind, distance and calories; no key and no new Apple capability.

## Capabilities

### New Capabilities

- `relay-health-nights-workouts`: the phone groups sleep readings into nights per source, each with its stage timeline, and sends each workout with its kind, distance and calories; it reads sleep and workouts back 36 hours and redoes the last 90 days once; the server keeps nights, fills workout details, sends both to webhooks ticked for Health, and gives them to the AI connector and the `/v1/` API.

### Modified Capabilities

None.

## Impact

- Phone, pure: `mobile/lib/sync/nights.dart` (new): sleep readings to nights, per source, no I/O; `nights_test.dart`.
- Phone, health: `mobile/lib/sync/health.dart` (read the sleep stage types and, on Android, ask for distance and calories; workout `kind`, `distance`, `calories` on a `workout` sample; the 36-hour read for sleep and workouts; the `health.detail` 90-day redo; the sent list for nights and workouts); `health_test.dart`.
- Phone, data: `store.dart` (a `nights` outbox route in `privateRoutes`, `queueNights`), `api.dart` (`POST nights`), `webhook.dart` (`health.nights`, workout fields on `health.samples`), `outbox.dart` (`nights` marks *Sent* for Health).
- Android: `AndroidManifest.xml` gains `READ_DISTANCE` and `READ_TOTAL_CALORIES_BURNED`.
- Server: `schema/space-migrations/0014_nights.sql` (`relay_nights`; `relay_health` gains `kind`, `distance`, `calories`; `relay_outbox` rebuilt with the `night` kind; a trigger logs a workout whose details fill); `app/worker/apps/relay/nights.ts` (`POST nights`); `samples.ts` (workout fields, fill on resend); `caller.ts` (`REACH.phone` gains `nights`); `kinds.ts` (`health.nights` under *Health*); `webhooks/format.ts`; `queries.ts` (`nightPage`, `workoutPage`, `daySummary` adds `nights` and `workouts.items`); `api.ts` (`GET /v1/nights`, `GET /v1/workouts`); `relay-mcp/answers.ts`, `inputs.ts`, `openapi.ts`, `tools.ts`; `npm run relay:api-doc`.
- Docs: `site/src/content/docs/app/health.md`, `connections/connect-your-ai.md`, `connections/your-database.md`, `privacy.md`; `site/public/webhooks/receiver.mjs`; `wiki/relay-phone-sync.md`, `wiki/relay-space-migrations.md`, `wiki/stack/relay-ai-connector.md`.

## Decision log

- **2026-11-09** — Asked (in the other chat) whether health needs work on the phone like location → chose its own change, apart from the phone data viewer: the server already sums day totals, and what is lost is lost on the phone.
- **2026-11-09** — Asked where a night is worked out → chose on the phone, like stays, so the person's own webhook gets whole nights too.
- **2026-11-09** — Asked what happens to sleep and workouts already sent → chose redo the last 90 days once, a week each round.
- **2026-11-09** — Asked where nights and workouts show → chose the AI, webhooks and the API; the web page keeps its Sleep tile, and the phone data viewer can show nights later.
- **2026-11-09** — Assumed: the phone keeps sending `sleep` samples as today beside the nights, because the day's sleep total, the *health* read and older receivers use them.
- **2026-11-09** — Assumed: sleep and workouts read back 36 hours each round, not 2, because an Apple Watch writes the whole night at wake while heart rate wakes the phone each hour of the night; with only 2 hours, the start of the night can be lost. Not seen on a real iPhone yet: the simulator has no health data.
- **2026-11-09** — Assumed: the phone keeps a short list of the nights and workouts it sent in the last 48 hours, by a hash of their fields, because the 36-hour read would otherwise send each night to the person's own webhook about 24 times.
- **2026-11-09** — Assumed: a night is per source, and readings more than 2 hours apart start a new night, because a watch and the phone's own bedtime each write the same night, and their stages must not add up.
- **2026-11-09** — Assumed: a read gives, of nights that overlap, the one with the most minutes asleep, as the day total takes the largest source.
- **2026-11-09** — Assumed: workout details go as three optional fields on today's `workout` sample, and a resend fills them on a row that has none, because a workout is already one row, and receivers keep working with fields added.
- **2026-11-09** — Assumed: Android's calories are total calories, as the health package reads them, and the Health page says so, because the package does not read active calories for a workout.
- **2026-11-09** — Assumed: a nap is a night, with no nap flag, because the AI can tell a 14:00 sleep from its times.
- **2026-11-09** — Assumed: two new read-only AI tools, *nights* and *workouts*, and `GET /v1/nights` and `GET /v1/workouts`, because the *health* read gives one number per hour or day and can't hold a list.
- **2026-11-09** — Assumed: no overlap with the phone data viewer (in its own workspace): it reads the day summary, which only gains fields here.
- **2026-11-09** — Asked whether a night and a stay link to their raw data → answered: only by device and time; a stay's points are on the server but no read gives them, and this plan's nights would keep no stage detail.
- **2026-11-09** — Asked what to do about it → chose my recommendation: each night carries its stage timeline in this plan; a read of the points behind a stay or trip goes in its own plan, opened in the workspace "See the points behind a stay or trip"; heart rate during workouts and nights waits for later.
- **2026-11-09** — Assumed: the timeline sits inside the night, not as a stage on each raw `sleep` sample, because older servers and receivers would count awake samples as sleep.
- **2026-11-09** — Assumed: the *nights* read gives the timeline only when asked (`stages`), because a month of nights with 50 steps each would make a long answer.
- **2026-11-09** — Assumed (build): on Android, the health package reads a workout's distance and total calories inside its time with no check, so a person who refuses *Distance* or *Total calories burned* gets no Android workouts at all, as before this change, when the app never asked for them. The app still asks, the Health page says so, and the spec scenario *Calories refused on Android* now says this. Sending workouts without them needs a patched package.
- **2026-11-09** — Assumed (build): the *nights* and *workouts* reads page with `cursor` and answer `nextCursor`, a time as text, like *search* and *calendar*, not `next`, so every newest-first read in the connector reads on the same way.
- **2026-11-09** — Assumed (build): the phone queues nights 30 to an upload, not 500, so 30 nights with full 400-step timelines stay under the route's 1 MB limit.
- **2026-11-09** — Assumed (build): on Android, a sleep session with no stage that says how the person slept counts as asleep, less the awake time in it; a night's `asleep` is the union of its asleep, core, deep and REM readings.
- **2026-11-09** — Assumed (build): the redo reads each week plus 2 hours before and one day after, and keeps only the nights and samples that start in its week, so a night across two weeks goes once whole. It starts at the first round after the app asked for the new types. The 90-day history of other types no longer reads sleep and workouts, as the redo does.
- **2026-11-09** — Assumed (build): the phone's sent list keys each row by its start first, and forgets it 48 hours after that start; the hash is the first 16 hex digits of the SHA-256 of the row's JSON.
- **2026-11-09** — Assumed (build): the example receiver keeps a workout's details in a new `workouts` table beside `health_samples`, and nights in `health_nights`, so a receiver's old database file keeps working with no change to its tables.
- **2026-11-09** — Assumed (build): the day summary for the Relay Everything page (`GET summary`) gains `nights` and `workouts.items` too, as it shares `daySummary` with the AI; the page shows neither yet.
- **2026-11-09** — Assumed (build): the plan's test gates between parts moved to the end of the build, with their checks kept.
- **2026-11-10** — Assumed: a health sample's id comes from its type, start, end and source, and the example receiver keeps a sample once by those fields, because the 90-day redo would otherwise double sleep and workouts in a person's own database; the reviewer's recommendation, plus the receiver rule for samples sent before with older ids.
- **2026-11-10** — Checkpoint: built and reviewed twice (the redo doubling samples in a person's own database fixed; the example Postgres table keeps a sample once by its fields); the local checks pass, with 585 phone tests. Left: the staging check (6.2).
- **2026-11-10** — Assumed: the final check (6.2) ran on this computer against the branch's own server and AI connector, not on staging, because staging's preview has no person spaces and its shared space must not take made-up health rows; the places change checked the same way. Seen: a night sent twice stored once, an old workout gained its kind when sent again with details, *nights* (with and without `stages`), *workouts* and the day read gave each once, the outbox held one `night` row that only the Health-ticked webhook waited on, and both keys answered 403 after *Turn off*.
- **2026-11-10** — Archive checkpoint: every task done, the final check passed on this computer; archived for publishing.
- **2026-11-10** — Archive checkpoint: main merged in (notes first, ring removed, sign-in from webhook); the four text conflicts kept both sides, and `nights` stays in the phone's private routes, so nights wait behind notes as health does.
- **2026-11-10** — Archive checkpoint: main merged in again (the web page becomes the phone app); the Health doc keeps both its new wording and `health.nights`. The phone tests run again on GitHub, as Matthew chose, after two timing-based voice-note tests failed once each.
