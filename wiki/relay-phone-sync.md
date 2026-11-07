# How the phone sends health and the calendar

The Relay Everything phone app reads health and calendar events only while sending is on, and sends them to the person's space in small uploads, a little each round. This page tells the rules that keep a round short and a resend harmless. It is part of [the wiki](README.md); [`mobile/README.md`](../mobile/README.md) owns where the phone's code is, the website's [Health](../site/src/content/docs/app/health.md) and [Calendar](../site/src/content/docs/app/calendar.md) pages own what a person reads, and the shipped [sync](../openspec/specs/relay-sync/spec.md) and [sending](../openspec/specs/relay-sending/spec.md) specs own what it must do.

## The round

`backgroundRound` in [`background.dart`](../mobile/lib/sync/background.dart) runs for Android's hourly task, for each iPhone wake, and at app open. It drains the iPhone's places, reads health, reads the calendar, queues the uploads and flushes them. An iPhone wake has about 25 seconds, so a round must never read all of a long history at once. There is no calendar wake: the calendar goes with the wakes for health and places.

## Health: new readings first, then 90 days back

1. **New readings.** The round reads from the state key `health.since`, with a 2-hour overlap, so a late reading is not lost. This read always runs first, so new readings never wait behind history.
2. **History, one week a round.** The state key `health.backfill` holds the oldest day read so far. While it is newer than 90 days ago, the round reads the 7 days before it, queues them in 500-sample uploads, and moves the mark. One 90-day read fails: an Apple Watch writes thousands of heart readings a day, past the wake's time and the phone's memory.
3. **An updated phone.** A phone with `health.since` and no `health.backfill` starts its backfill at the first read of `health.since`, so the 90 days also fill the new types.
4. **New types.** The state key `health.types` holds the types the phone asked for. When the app knows more types than that list, it asks once at the next open. A type the person refused reads as empty, not as an error.

Each type maps to one server name and one unit in [`health.dart`](../mobile/lib/sync/health.dart), and the server checks the name against `HEALTH_TYPES` in [`queries.ts`](../app/worker/apps/relay/queries.ts), never in SQL ([person spaces](relay-spaces.md#space-migrations)). The server keeps each sample once, so a resend after a lost answer is harmless. Heart rate variability stays two types, `hrv_sdnn` (iPhone) and `hrv_rmssd` (Android): the two measures can't be averaged together.

## Calendar: send only what changed

1. **The window.** Each round reads the events from 90 days ago to 90 days ahead, from every calendar not in `Settings.calendarsOff`.
2. **The key.** An event's key is `<calendar id>:<event id>:<start in ms>`, so each time of a repeating event is its own row.
3. **The diff.** The phone's table `calendar_sent (key, hash)` keeps the SHA-256 of each sent event's fields. The round queues each event whose hash is new or changed, and, as `removed`, each key in `calendar_sent` that is gone from the window's read. Uploads hold up to 200 events. The first round sends the whole window by the same code.
4. **One transaction.** The round writes `calendar_sent` in the same transaction as the upload, so a crash never marks an event sent that has no upload.
5. **The past edge.** A key that leaves the window's past edge is dropped from `calendar_sent` with no removal: the event happened, and the space keeps it.
6. **Off.** A calendar turned off has its keys removed at the next round, by the diff. Turning the calendar or sending off deletes waiting `calendar` uploads and empties `calendar_sent`, so turning it on again sends the window again.

A full copy each hour is wrong: a few hundred events pass the 256 KB body cap, and every webhook gets every event each hour. The server's `POST calendar` upserts only when a field differs ([person spaces](relay-spaces.md#space-migrations)), so a resend changes nothing and wakes no webhook.

## See also

- [Relay Everything's person spaces](relay-spaces.md): where the samples and events are kept, and the webhooks that send them on.
- [Relay Everything's AI connector](stack/relay-ai-connector.md): the `health` and `calendar` tools that read them.
- [The device check](development/device-check.md): the iPhone simulator has no health data, so check health on a real iPhone.
