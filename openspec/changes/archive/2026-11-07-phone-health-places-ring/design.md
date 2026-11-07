## Context

See proposal.md - Why. Today, on iPhone:

- Health is read by the `health` plugin in `lib/sync/health.dart`, from the app's own round and from the hourly `workmanager` task (`lib/sync/background.dart`). iOS runs a `BGTaskScheduler` task when it likes, often not for days, so the hourly round is not a promise. `Runner.entitlements` already holds `com.apple.developer.healthkit.background-delivery`, but no code asks for it.
- Location history is a `geolocator` stream that `RelayController` starts in the app's own process (`controller.dart` `_startHistory`). It keeps going in the background only while iOS keeps the process; once iOS ends it, or the phone restarts, no point is kept until the person opens the app.
- A phone gets its key only from the QR code that *Add a device* shows (`screens/connect.dart`). The AI connector already has a hand-off through sign-in (`app/worker/apps/relay/sign-in/connect.ts`): a code that works once, kept as its SHA-256 in `relay_connect_codes`.

## Goals / Non-Goals

**Goals:** health and places reach the space with the app closed on iPhone; one code path per platform for history; a phone key made by signing in, with no key on any screen.

**Non-Goals:** Android background changes; a new health type; the ring (workspace *Connect the Pebble ring over Bluetooth*); sending to a webhook from the phone.

## Decisions

### 1. One native wake, one Dart round

A Swift `BackgroundWake` class owns every iPhone wake-up. On a wake it starts a headless `FlutterEngine` on the Dart entry point `wakeRound` (`lib/sync/wake.dart`, `@pragma('vm:entry-point')`), registers the plugins, calls `relay/wake` `round`, and ends the engine and the iOS background task when Dart answers or after 25 s. `wakeRound` runs `backgroundRound` (the same round the hourly task runs, with sending checked first) and answers true or false.

- *Over* a `workmanager` one-off task from native: iOS schedules those itself, so the wake would wait again.
- *Over* reading Health in Swift and posting from Swift: the outbox, the sending switch and the server's shape stay in one place, in Dart, with their tests.

The hourly `workmanager` task stays as a backup.

### 2. Health: observer queries with hourly background delivery

In `didFinishLaunchingWithOptions` (iOS needs it there, on each launch), when the native flag `health` is on, Swift adds one `HKObserverQuery` per type the app reads (steps, heart rate, sleep analysis, workouts) and calls `enableBackgroundDelivery(for:frequency: .hourly)`. Each observer callback runs one wake (at most one at a time; a second callback while one runs only waits for it) and calls its completion handler after. When the flag goes off, Swift calls `disableAllBackgroundDelivery` and stops the queries.

A locked iPhone refuses Health reads (`errorDatabaseInaccessible`). `syncHealth` then throws before it moves `health.since`, so the next wake reads the same window again. A test covers this.

### 3. Places: native location manager on iPhone, in OwnTracks' two modes

On iPhone, Swift owns history with one `CLLocationManager`, after [OwnTracks' `LocationManager.m`](https://github.com/owntracks/ios/blob/master/OwnTracks/OwnTracks/LocationManager.m) (read at `bbb7b76`; we copy its approach, not its code):

| Mode | iOS calls | Point kept | Wake to send |
|---|---|---|---|
| `battery` (default) | `startMonitoringSignificantLocationChanges` + `startMonitoringVisits`; on each wake, `requestLocation` | each significant change (about 500 m, at most each 5 min) and each visit arrival and departure | each wake |
| `move` | `startUpdatingLocation`, `distanceFilter` none, best accuracy, `pausesLocationUpdatesAutomatically = NO`, plus significant changes for relaunch | when 100 m from the last kept point, or a 5-minute timer | at most each 5 min |

Both set `allowsBackgroundLocationUpdates`. Significant changes relaunch the app after iOS ends it or the phone restarts; a relaunch reads the mode from `UserDefaults` and starts it again, as OwnTracks' `wakeup` does. A visit keeps `manager.location`, as OwnTracks does, so a visit is a point like any other and the server's `locations` route needs no change.

Each point goes to a JSON-lines file in Application Support, excluded from backup. Dart drains the file in each round (`store.addPoint`), then `queuePoints` and flush send them as now. While the app is open, the controller drains the file each minute, so the timeline's pins and ring-note places do not wait.

- *Over* our first draft (100 m updates with automatic pause, all the time): that drains more than significant changes and still stops when iOS pauses updates; OwnTracks shows the two clean ends.
- *Over* sending each point from Swift, as OwnTracks' HTTP mode does: the outbox, the sending switch and the key stay in Dart, in one place, with their tests.
- *Over* keeping the geolocator stream and adding only significant changes: two location managers would fight over settings, and a relaunched app has no Flutter engine to hold the stream.
- On Android, `PhonePlaces.history()` stays the source, with no mode choice.

Points from the file carry no place name. The round names at most 10 of them through `geocoding` while sending is on (Apple limits how often an app may look up names), newest first; the rest stay unnamed, as a point with no signal does today.

### 4. Native flags follow the settings

Dart tells Swift through `relay/background` `set` `{health, history, mode}` each time the settings change and at app start, computed as `sending && health` and `sending && history`. Swift keeps them in `UserDefaults`, because a relaunch reads them before any Dart runs. Off stops the queries, the location manager and significant-change monitoring at once, and deletes the points file. This keeps the promise in `relay-sending`: nothing is read or kept while sending is off.

### 5. Connect by signing in: a one-time code with a proof key

```text
App                        Server (sign-in)                         Directory
 |-- open phone?challenge&name ->|  not signed in -> sign-in page, then back
 |                              |  "Connect this phone?" + name field
 |                              |-- POST phone (Origin checked) -------->| relay_phone_codes: code_sha256, person, name, challenge, expires (5 min)
 |<- relayeverything://connected?code -|
 |-- POST phone/key {code, verifier} ->|  SHA-256(verifier) == challenge, row deleted
 |                              |  make the phone device and key, as Add a device does
 |<- {server, key} -------------|
```

- `GET /apps/relay/sign-in/phone` and `POST /apps/relay/sign-in/phone` sit beside `connect.ts`. The page is plain server HTML with the site's look; *Cancel* returns `relayeverything://connected?error=cancelled`.
- `POST /apps/relay/sign-in/phone/key` is exempt from the Origin check, like `apple/callback`: the verifier, not the Origin, protects it. It is limited by `RELAY_SIGN_IN_LIMIT` per address.
- The key is made only at the trade, so the directory never holds a key, only its SHA-256, as now. The device-making part of `deviceAdd` moves to one shared function so both ways make the same rows (a phone device has its Pebble secret, never shown here).
- The app uses `flutter_web_auth_2` (`ASWebAuthenticationSession` on iPhone, a Custom Tab on Android) with callback scheme `relayeverything`, and makes the verifier from 32 random bytes. It then checks the key with `GET key`, as a scanned key is.
- *Over* a universal link: it needs an `apple-app-site-association` file on each self-hosted server. The confirm page, the 5-minute code and the verifier keep a custom scheme safe enough: another app that grabs the return gets a code it can't trade.
- Default server `https://app.relayeverything.com`; *Use another server* takes an https origin through `Connection.serverOf`.

### 6. Last sent, per kind

`flush` records `sent.health` and `sent.points` (milliseconds) in the store when an upload of that kind lands. Settings reads them with the waiting counts (outbox rows by kind, plus unqueued points). Times show as `HH:mm` today, else the date.

## UX

### Use-case brief
One person, on their own iPhone, sets this up once and then forgets it. Done is: health and places show on their Relay Everything page each day with the app never opened. The common case is the shared server; a self-hoster is the edge case. Mirror today's *Connect Relay Everything* and *Settings* screens.

### Flow
Settings → *Location history* on → *Save battery* is chosen; *Every 100 m* is one tap below it.

Settings → *Send to Relay Everything* on → *Connect Relay Everything* → *Sign in to connect* → sign in → *Connect* → back in the app, connected, *Send your earlier notes too?* if any. QR and paste branch off below the button.

### Hierarchy
Connect: *Sign in to connect* is the one primary action; *Use another server*, *Scan the QR code* and paste are quieter. Confirm page: *Connect* is primary, *Cancel* quiet. Settings: the status lines are muted text under each switch, never a button. The two location modes are a radio pair shown only while *Location history* is on.

### Review
[review.html](review.html): What Changes items 2 (location modes), 3 (connect and confirm) and 4 (Settings) sketch each screen.

### Components
Existing Material `FilledButton`, `OutlinedButton`, `TextButton`, `SwitchListTile` subtitles, `RadioListTile` for the location modes. The confirm page reuses the sign-in page's layout and styles. Nothing new.

## Risks / Trade-offs

- [iOS decides when to wake an app; "hourly" is a most, not a least] → The Settings line shows the last send, and the device check plus the person's walk confirm it on a real phone.
- [A person who force-quits the app stops significant-change relaunch until they open it] → iOS rule; the *Location* page says so.
- [*Every 100 m* drains the battery like navigation] → *Save battery* is the default; the mode's subtitle says so, as OwnTracks' guide does.
- [*Save battery* keeps few points in a city walk under 500 m] → Visits add arrival and departure; a person who wants more chooses *Every 100 m*.
- [A headless engine costs memory and time] → One wake at a time, 25 s cap, at most one location wake each 5 minutes.
- [Apple review asks why the app uses Always location and Health in the background] → Usage strings already say it; the app is on TestFlight for its owner only.
- [Changing the iPhone history source loses points the old stream held in memory] → It held none on disk; points already in the store stay.

## Migration Plan

1. The server change ships first: the directory migration (`relay_phone_codes`), then the shared server, deployed by hand as [person spaces](../../../wiki/relay-spaces.md#the-workers-and-their-order) says. Old apps don't call the new routes.
2. The app update ships on the next publish to TestFlight. A phone that already has a key keeps it; the new connect only matters to a new connect.
3. Rollback: the old app build on TestFlight; the new routes can stay, as nothing else calls them.
