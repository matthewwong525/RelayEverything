# Make health, places and connecting work on the iPhone

**Status:** ready-to-ship
**Branch:** ios-app-health-ring-webhooks
**Open questions:** none

## Why

The iPhone app already reads Apple Health and keeps your places, but only while the app is open. The iPhone stops an app soon after you leave it, so health and places stop going to your space. Connecting the phone is also hard: you need a second screen to show a QR code.

## What Changes

- **Health keeps going when the app is closed.** Apple Health tells the app when it has new steps, heart rate, sleep or workouts, at most once an hour. The iPhone then wakes the app for a short time, and the app sends the new readings to your space. The hourly round stays as a backup. A locked iPhone does not let any app read Health, so the app reads again at the next wake-up.
  ```mermaid
  sequenceDiagram
    participant H as Apple Health
    participant A as App, woken
    participant S as Your space
    H->>A: New readings
    A->>H: Read since last time
    A->>S: Send them
    S-->>A: Kept once
  ```
- **Places keep going when the app is closed or the phone restarts, the way OwnTracks does it.** *Location history* gets two ways to keep your places, as the open-source app [OwnTracks](https://owntracks.org/booklet/features/location/) has. Both keep going after the app closes or the phone restarts. Only a swipe up that closes the app stops them, until you open it again: the iPhone's rule. With *Location history* off, the app asks for no wake-ups. The two ways:
  - **Save battery** (the default): the iPhone wakes the app when you move about 500 m, at most each 5 minutes, and when you arrive at or leave a place. Each wake-up keeps a point and sends it. This costs almost no battery.
  - **Every 100 m**: a point each 100 m you move, or each 5 minutes when you stay still. It uses as much battery as a map app giving directions, so use it on a trip or while charging.
  ```mermaid
  flowchart TD
    M["You move 500 m, arrive or leave"] --> W["iPhone wakes the app"]
    W --> P["Keep a point"]
    P --> S["Send to your space"]
    C["App closed or phone restarted"] -.-> M
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><div class="col grow"><b>Location history</b><span class="muted">Sent 10:40 · 3 points waiting</span></div><span class="tag">On</span></div>
    <div class="row gap"><div class="col grow"><b>Save battery</b><span class="muted">When you move 500 m, arrive or leave</span></div><span class="tag">Chosen</span></div>
    <div class="row gap"><div class="col grow"><b>Every 100 m</b><span class="muted">Or each 5 minutes. Uses more battery: for trips</span></div><span class="tag-outline">Choose</span></div>
  </div>
  ```
- **You connect the phone by signing in from the app.** *Connect Relay Everything* gets *Sign in to connect*. It opens your Relay Everything sign-in inside the app. After you sign in, the page asks *Connect this phone?* with its name, and *Connect* gives this phone its own key. The key goes straight to the phone and never shows. The server is `app.relayeverything.com`; *Use another server* takes your own server's address. *Scan the QR code* and *Or paste the key* stay. This works on Android too.
  ```screen
  <div class="row gap">
  <div class="card col gap phone">
    <h3>Connect Relay Everything</h3>
    <p class="muted">Sign in, and this phone gets its own key. It can only add notes, health and places to your space.</p>
    <button class="btn-primary">Sign in to connect</button>
    <button class="btn-ghost">Use another server</button>
    <div class="sep"></div>
    <p class="muted">Or use a key from Add a device</p>
    <button class="btn-ghost">Scan the QR code</button>
    <input class="field" placeholder="Or paste the key">
  </div>
  <div class="card col gap phone">
    <h3>Connect this phone?</h3>
    <input class="field" value="Matthew's iPhone">
    <p class="muted">It can add notes, health and places to your space. It can't read them. You can turn it off on this page.</p>
    <button class="btn-primary">Connect</button>
    <button class="btn-ghost">Cancel</button>
  </div>
  </div>
  ```
  A sketch, not a prototype: the phone app can't run as a web preview. The left is the app; the right is the sign-in page inside it.
- **Settings shows that it works.** Under *Health* and *Location history*, a line says when each last went to your space, and how many wait. You see at once if the iPhone stopped them.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><div class="col grow"><b>Send to Relay Everything</b><span class="muted">app.relayeverything.com</span></div><span class="tag">On</span></div>
    <div class="sep"></div>
    <div class="row gap"><div class="col grow"><b>Health: steps, heart rate, sleep, workouts</b><span class="muted">Sent 10:42 · none waiting</span></div><span class="tag">On</span></div>
    <div class="row gap"><div class="col grow"><b>Location history</b><span class="muted">Sent 10:40 · 3 points waiting</span></div><span class="tag">On</span></div>
  </div>
  ```
- **The website and the app's guide say the new way.** *Connect a phone*, *Health* and *Location* say how to sign in from the app, and when the iPhone sends.

Non-goals: the Pebble ring over Bluetooth (its own plan, in another workspace), background changes on Android (it already sends in the background), sending straight to a webhook with no space, and new health types.

## What the build needs

- **Apple Health background wake-ups**: Ready, the app's signing file already allows them.
- **App Store Connect key for TestFlight builds**: Ready, in `.env` and the repository's secrets.
- **Your iPhone with TestFlight**: Ready, you have the app. After the build you walk with it and look at your page.

## Capabilities

### New Capabilities
- `relay-app-background`: on iPhone, health and location history keep reaching the person's space while the app is closed, through HealthKit background delivery and, after OwnTracks, two location modes (significant changes with visits, or every 100 m / 5 minutes); Settings shows when each last sent.

### Modified Capabilities
- `relay-device-keys`: a phone can also get its key by its person signing in from the app and confirming, with the key handed to the phone through a one-time code, never shown.

## Impact

- `mobile/ios/Runner/`: Swift for HealthKit observer queries, significant location changes and a headless engine that runs one Dart round; `Info.plist` URL scheme for the sign-in return.
- `mobile/lib/`: a background entry point, the connect screen, Settings status lines, the last-sent record in the store; one new package for the in-app sign-in (`flutter_web_auth_2`).
- `app/worker/apps/relay/`: a phone connect page and a code-for-key route; a directory migration for one-time phone codes; the API doc.
- `site/` pages *Connect a phone*, *Health*, *Location*, *Keys*; `mobile/README.md`.

## Decision log

- **2026-11-07** — Asked what goes wrong on the iPhone today → chose *haven't tried yet*: make health and places reliable in the background and add a way to see it works.
- **2026-11-07** — Asked which ring the app connects to → chose the Pebble Index 01.
- **2026-11-07** — Asked where the phone sends → chose your own space, as now, with an easier connect such as signing in from the app.
- **2026-11-07** — Asked again how to reach the ring, after research found its Bluetooth link is only in Pebble's compiled library → chose to plan the ring separately, in its own workspace.
- **2026-11-07** — Asked, in a note, to see how OwnTracks keeps places → chose its shape: a battery-saving mode on significant changes and visits as the default, and an every-100 m mode for trips.
- **2026-11-07** — Assumed: the note's *OnlyTracks* means OwnTracks, because no app of that name turns up and OwnTracks is the open-source location diary for iPhone.
- **2026-11-07** — Assumed: *Save battery* is the default, as in OwnTracks, because the every-100 m mode drains the battery like a map app.
- **2026-11-07** — Assumed: Android's background sending stays as it is, a point each 100 m with no mode choice, because it already works with its own notice and Health Connect's background permission; the new connect works on both.
- **2026-11-07** — Assumed: the connect page asks *Connect this phone?* before it makes a key, because a link that made a key with no question could hand a key to another app.
- **2026-11-07** — Assumed: Settings shows when health and places last sent, because the simulator check can't test Health and you need to see it work on your phone.
- **2026-11-07** — Assumed: the plan's test gates between parts moved to the end, as the build runs all tests once after all source and tests are written.
- **2026-11-07** — Assumed: the trade route `sign-in/phone/key` also passes Cloudflare Access on a self-host, through the worker's exemption and the keys app's destinations, which `self-host/setup.mjs` update adds to an older install, because the app must reach it with no sign-in.
- **2026-11-07** — Assumed: the trade vouches with a new caller kind, `code`, and `sign-in/phone.ts` joins the space-access check's list of vouchers, because the code and its secret are that file's own check of the person.
- **2026-11-07** — Assumed: a wrong secret ends the code, so a caught code gets one try only.
- **2026-11-07** — Assumed: Dart tells Swift a wake's round is done on `relay/wake`, in place of Swift calling the round, so one Dart entry point serves the closed and the open app; with the app engine running, the wake runs there.
- **2026-11-07** — Assumed: a closed or cancelled sign-in shows no message, and the phone's name starts as *iPhone* or *Android phone*, which the person can change on the page.
- **2026-11-07** — Assumed: `fake_async`, already in the lockfile through `flutter_test`, becomes a dev dependency to test the one-minute drain with no real wait.
- **2026-11-07** — Assumed: `flutter build ios` can't run on this Linux computer, so task 3.3's build check waits for the iPhone device check in task 5.2.
- **2026-11-07** — Assumed: the phone keeps its key in the iPhone Keychain with *after first unlock, this device only* (`first_unlock_this_device`), and the open app saves a key from an earlier version again at start, because with the default a wake on a locked phone can't read the key and sends nothing.
- **2026-11-07** — Assumed: a drain stores every point before it looks up any name, in place of Swift keeping its file until Dart confirms, because iOS can end a wake during the slow lookups, and then only names are lost, never points.
- **2026-11-07** — Assumed: one wake that a late answer from an earlier, already-ended wake reaches does not end the new wake early; Swift counts the wakes to check this, because the new iOS background task would end with it.
- **2026-11-07** — Built and reviewed inside `/ship`: tasks 1.1–5.1 done, local checks and `flutter test` pass, a second look found five background-path faults, all fixed and reread clean; saving for the iPhone device check (5.2), which first compiles the Swift.
- **2026-11-07** — Final acceptance: the staging migration ran in CI, the staging shared server was deployed by hand and its phone routes answered (signed out → sign-in; a bad code → 400), and the iPhone device check on `d2fa165` gave *works* (location modes could not be checked with no key). The sign-in sheet showed *Not found* on app.relayeverything.com, because the live shared server is deployed by hand after the merge.
- **2026-11-07** — Assumed: task 5.3, the person's own TestFlight walk, moves out of the task list to an open item after publish, because it can only run on the published build and a merge must not wait on it.
- **2026-11-07** — Archived for publish; main specs already hold the deltas.
