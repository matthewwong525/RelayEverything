# How the phone sends health, places and the calendar

The Relay Everything phone app reads health, places and calendar events only while sending is on, and sends them to the person's space in small uploads, a little each round. This page tells the rules that keep a round short and a resend harmless. It is part of [the wiki](README.md); [`mobile/README.md`](../mobile/README.md) owns where the phone's code is, the website's [Health](../site/src/content/docs/app/health.md), [Location](../site/src/content/docs/app/location.md) and [Calendar](../site/src/content/docs/app/calendar.md) pages own what a person reads, and the shipped [sync](../openspec/specs/relay-sync/spec.md) and [sending](../openspec/specs/relay-sending/spec.md) specs own what it must do.

## The round

`backgroundRound` in [`background.dart`](../mobile/lib/sync/background.dart) runs for Android's hourly task, for each iPhone wake, and at app open. It drains the iPhone's places, reads health, reads the calendar, steps the [stays and trips](#places-stays-and-trips), queues the uploads and flushes them. An iPhone wake has about 25 seconds, so a round must never read all of a long history at once. There is no calendar wake: the calendar goes with the wakes for health and places.

## Health: new readings first, then 90 days back

1. **New readings.** The round reads from the state key `health.since`, with a 2-hour overlap, so a late reading is not lost. This read always runs first, so new readings never wait behind history.
2. **History, one week a round.** The state key `health.backfill` holds the oldest day read so far. While it is newer than 90 days ago, the round reads the 7 days before it, queues them in 500-sample uploads, and moves the mark. One 90-day read fails: an Apple Watch writes thousands of heart readings a day, past the wake's time and the phone's memory.
3. **An updated phone.** A phone with `health.since` and no `health.backfill` starts its backfill at the first read of `health.since`, so the 90 days also fill the new types.
4. **New types.** The state key `health.types` holds the types the phone asked for. When the app knows more types than that list, it asks once at the next open. A type the person refused reads as empty, not as an error.

Each type maps to one server name and one unit in [`health.dart`](../mobile/lib/sync/health.dart), and the server checks the name against `HEALTH_TYPES` in [`queries.ts`](../app/worker/apps/relay/queries.ts), never in SQL ([person spaces](relay-space-migrations.md)). The server keeps each sample once, so a resend after a lost answer is harmless. Heart rate variability stays two types, `hrv_sdnn` (iPhone) and `hrv_rmssd` (Android): the two measures can't be averaged together.

## Places: stays and trips

The phone makes stays and trips from its own points, in [`stays.dart`](../mobile/lib/sync/stays.dart), with no network call. The constants at the top of that file give each rule's number, such as 100 m for a stay and 30 minutes of silence.

1. **Only the open part is kept.** The phone keeps only the open stay or trip. The state key `stays.timeline` holds it, and the tables `track` and `motions` hold its points and motion changes. Each round replays the points after the state's cursor and sends each stay or trip that ended. A stay goes as `ongoing` when it starts, again each round its end moves on (its newest point, or the round's time while the phone is still with no new point), and again with its end. The server and a webhook keep it by its device, kind and start, so each send changes the one before. A late point, one the store marks because it came after a round stepped past its time, at the place of the last stay, before the point that ended it, moves that stay's end while the trip after it is open: an iPhone visit's departure often comes after the move.
2. **One transaction.** `queueStays` in [`store.dart`](../mobile/lib/data/store.dart) saves the uploads, the state and the drop of old rows in one step. If iOS stops a round before that step, the next round does the step again from the same points.
3. **Not `timeline`.** The app deletes the state key `timeline` at each open: older versions used it. Do not use that key again.
4. **Motion.** [`motion.dart`](../mobile/lib/sync/motion.dart) reads what kind of moving the person did, never steps. On iPhone, Core Motion keeps 7 days, and the round reads them on the `relay/background` channel. On Android, `ActivityReceiver.kt` writes each change to `relay-motion.jsonl`, also with the app closed, and the round reads and empties that file. Android forgets its request after a restart, so the app makes it again at each open. With no motion, or a no, the mode comes from speed.
5. **A visit gives two points.** On iPhone, a place visit adds a point when it began and one when it ended, so a stay that the phone saw only as a visit has its true times.
6. **Names, at most 3 a round.** [`stay_round.dart`](../mobile/lib/sync/stay_round.dart) names a stay from the calendar, then Apple Maps, then the street, then the coordinates. Each is a network call, so the round makes it only while sending is on. A stay with no name yet goes as its coordinates, with `source: point`.
7. **What to send.** `Settings.locationSend` is `all`, `stays` or `points`. With `stays`, no point waits to go as a point, and the change drops the points that wait. With `points`, the phone makes no stays and keeps no motion. Location history off, or a change to `points`, with sending on, first queues the open stay ended at the later of its last point and the end already sent (`closeTimeline`), so the server does not keep it ongoing. Sending off drops the open stay, its points, its motion and the waiting `stays` uploads; the server reads a stay not sent for 6 hours as ended.

## Calendar: send only what changed

1. **The window.** Each round reads the events from 90 days ago to 90 days ahead, from every calendar not in `Settings.calendarsOff`.
2. **The key.** An event's key is `<calendar id>:<event id>:<start in ms>`, so each time of a repeating event is its own row.
3. **The diff.** The phone's table `calendar_sent (key, hash)` keeps the SHA-256 of each sent event's fields. The round queues each event whose hash is new or changed, and, as `removed`, each key in `calendar_sent` that is gone from the window's read. Uploads hold up to 200 events. The first round sends the whole window by the same code.
4. **One transaction.** The round writes `calendar_sent` in the same transaction as the upload, so a crash never marks an event sent that has no upload.
5. **The past edge.** A key that leaves the window's past edge is dropped from `calendar_sent` with no removal: the event happened, and the space keeps it.
6. **Off.** A calendar turned off has its keys removed at the next round, by the diff. Turning the calendar or sending off deletes waiting `calendar` uploads and empties `calendar_sent`, so turning it on again sends the window again.

A full copy each hour is wrong: a few hundred events pass the 256 KB body cap, and every webhook gets every event each hour. The server's `POST calendar` upserts only when a field differs ([person spaces](relay-space-migrations.md)), so a resend changes nothing and wakes no webhook.

## See also

- [Relay Everything's person spaces](relay-spaces.md): where the samples and events are kept, and the webhooks that send them on.
- [Relay Everything's AI connector](stack/relay-ai-connector.md): the `health`, `calendar` and `places` tools that read them.
- [The device check](development/device-check.md): the iPhone simulator has no health data, so check health on a real iPhone.
