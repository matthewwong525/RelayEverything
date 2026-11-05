# Relay app first version

**Status:** ready-to-ship
**Branch:** relay-app-first-version
**Open questions:** none

## Why

Relay's goal is the fastest way to capture a thought wherever you are. Before the Relay ring exists, Matthew's Pebble Index ring can stand in for it: its notes, plus the phone's health and location, should land in one place he owns, on both his iPhone and his Android phone.

## What Changes

- **Your ring notes land in Relay.** Each note from the Pebble ring arrives with its words and its recording, a few seconds after you let go. A note counts once, even when Pebble's app sends it again.
  ```mermaid
  flowchart TD
    A["Pebble ring: hold and talk"] --> B["Pebble app"]
    B -->|"signed webhook"| C["Relay on your site"]
    C --> D["Relay app timeline"]
  ```
- **A Relay app on iPhone and Android.** It opens on your notes, newest first, each with where it was taken. One tap writes a quick note.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><span class="tag-outline">Synced 2 min ago</span></div>
    <div class="card col"><span class="row gap"><span class="tag">Ring</span><span class="muted">9:41 · Queen St W</span></span><span>Call the PCB fab about the flex stiffener</span></div>
    <div class="card col"><span class="row gap"><span class="tag-outline">Typed</span><span class="muted">8:15 · Home</span></span><span>Order more TL3312 switches</span></div>
    <div class="row gap"><span class="grow"/><button class="btn-primary">New note</button></div>
  </div>
  ```
- **Health and location come along.** The app copies steps, heart rate, sleep and workouts from Apple Health or Health Connect, and keeps a location history as you move, so a ring note gets pinned to where you were. You turn each on in Settings, and can turn it off again.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><span class="grow">Health: steps, heart rate, sleep, workouts</span><span class="tag">On</span></div>
    <div class="row gap"><span class="grow">Location history</span><span class="tag">On</span></div>
    <div class="row gap"><span class="grow">This phone's key</span><span class="tag-outline">Connected</span></div>
    <button class="btn-ghost">Sync now</button>
  </div>
  ```
- **A Relay page on your site.** It shows the same notes, today's health and the places you've been. It also says how to set up the Pebble webhook, and links to the Android app and TestFlight.
  ```screen
  <div class="card col gap">
    <div class="row gap"><h3>Relay</h3><span class="grow"/><button class="btn-ghost">Set up a phone</button><button class="btn-ghost">Pebble webhook</button></div>
    <div class="row gap"><div class="card col grow"><span class="muted">Notes today</span><h3>6</h3></div><div class="card col grow"><span class="muted">Steps</span><h3>8,214</h3></div><div class="card col grow"><span class="muted">Places</span><h3>4</h3></div></div>
    <div class="card col"><span class="row gap"><span class="tag">Ring</span><span class="muted">9:41 · Queen St W</span></span><span>Call the PCB fab about the flex stiffener</span></div>
  </div>
  ```
- **Each phone and the Pebble app get their own key.** Only a device with a key can send to Relay, and one key can be turned off without touching the others.
- **New versions reach your phones by themselves.** Each publish builds the app in the public relay-app repository: an Android app file you download, and an iPhone build in TestFlight.
  ```mermaid
  flowchart TD
    A["publish"] --> B["relay-app on GitHub"]
    B --> C["Android app file"]
    B --> D["TestFlight"]
  ```
- **Apple's keys never go public.** The copy to relay-app also refuses Apple's signing key files, and Apple's keys stay in GitHub's secret settings.

Non-goals: watch apps, recording straight from the Relay ring, an open-source server, sending data on to your own database, a docs site, and an MCP server.

## What the build needs

- **Cloudflare token**: Ready, `CLOUDFLARE_API_TOKEN` is in `.env`.
- **GitHub sign-in for relay-app**: Ready, signed in as matthewwong525 with the workflow scope.
- **Apple Developer Program membership**: Needs you, for the TestFlight step only (task 7.4); everything else builds without it. Pay here, then the build sends a private link for the App Store Connect key: <https://developer.apple.com/programs/enroll/>
- **Your Pebble ring and both phones**: Ready, you have them; the build gives you the webhook address and key to enter in Pebble's app.

## Capabilities

### New Capabilities
- `relay-notes`: receiving signed Pebble Index webhooks and typed notes, de-duplicated, stored with audio and a location pin.
- `relay-sync`: phone upload of health samples and location history, idempotent, and the timeline read back.
- `relay-device-keys`: per-device keys that reach only Relay's routes and can be revoked one at a time.
- `relay-app-builds`: CI, Android release and TestFlight builds of `mobile/` in relay-app.

### Modified Capabilities
- `relay-app-publish`: the guard also refuses Apple signing files, and a branch can be pushed for a pre-publish build.

## Impact

- New: `app/worker/apps/relay/`, `app/src/apps/relay/`, a migration in `schema/migrations/`, rows in `schema/seed.sql`, R2 buckets `relay-ring-notes` and `relay-ring-notes-staging` bound as `RELAY_BUCKET` in `app/wrangler.jsonc`, `scripts/relay-device-key.mjs`, the Flutter project in `mobile/` with `mobile/.github/workflows/`.
- Changed: `scripts/publish-relay-app.mjs`, `AGENTS.md`'s Relay section, possibly the core app-permission check (device tokens), `.env.example` (App Store Connect key names).
- This computer: Flutter, the Android SDK and a JDK, several GB.
- Cloudflare: two R2 buckets, Access service tokens and one machine policy per environment.

## Decision log

- **2026-11-04** — Asked which phone the first version runs on → chose both iPhone and Android at once.
- **2026-11-04** — Asked how location is captured → chose both: each note pinned, and a background location history.
- **2026-11-04** — Asked where Relay's server lives for now → chose inside this project, private, movable later.
- **2026-11-04** — Asked whether a Pebble Index ring is on hand → chose yes, test with real ring notes.
- **2026-11-04** — Asked which phones are on hand → chose iPhone and Android phone.
- **2026-11-04** — Asked how test builds reach an iPhone → chose TestFlight, built on GitHub's Mac machines.
- **2026-11-04** — Assumed: health covers steps, heart rate, sleep and workouts, synced on open and hourly while the app runs, because those are the common ones both health stores offer.
- **2026-11-04** — Assumed: background location records on meaningful movement, not constant GPS, because it keeps battery use low.
- **2026-11-04** — Assumed: the Android app file is a GitHub release on relay-app, not a download on the private site, because the repository is public and its build machine makes the file anyway.
- **2026-11-04** — Assumed: a ring note takes the nearest location-history point within 10 minutes, because Pebble's webhook carries no location.
- **2026-11-04** — Assumed: device keys are Cloudflare Access service tokens, because both Pebble's webhook headers and the phone can carry them, and the site stays behind its login with no new public route.
- **2026-11-04** — Assumed: the phone screens are drawn as sketches, with no runnable prototype, because the phone app is Flutter, which this site can't run.
- **2026-11-04** — Assumed: Flutter's own tests run on relay-app's GitHub build machines and on this computer, not in this project's check runner, because the runner has no Flutter.
- **2026-11-05** — Asked whether an Apple Developer account is ready → chose: account exists but the paid membership is still to buy; build everything now and hold only the TestFlight step.
- **2026-11-05** — Asked how to handle webhooks out, the docs site and the MCP server → chose new workspaces now, each planning from this design and building after this change publishes.
- **2026-11-05** — Check: `scripts/check-private-access.mjs` and the login page's review in `app/worker/employee-access/login-management.ts` now accept one more Access policy, named "Relay devices", that holds only service tokens. Each device needs its own key that can be turned off alone, and the one machine-token policy holds exactly one. Both are WongStack files, so a later sync must keep this.
- **2026-11-05** — Check: `app/worker/apps/keys.test.ts` and `screenless.test.ts` now check Hello's key uses alone, and Relay's on its own line; the employee-access tests (`policy`, `seed`, `status`, `management`) expect the new Pebble key in every full key list; `app/worker/index.test.ts`'s fake database answers the device-key lookup, because the Worker now reads `relay_devices` for every service token. No limit or rule was loosened.
- **2026-11-05** — Assumed: a recording plays from `GET audio?id=`, and the timeline pages with `before` and `limit`, because both are plain reads the site and phones share.
- **2026-11-05** — Assumed: a note's place is stored on the note (coordinates, name, and whether the phone or the history gave it), and the phone names places itself, because the server has no address lookup.
- **2026-11-05** — Assumed: the summary takes the viewer's time zone as minutes east of UTC, and when two devices count the same steps or sleep, the larger count is the day's.
- **2026-11-05** — Assumed: Relay's Pebble route names its signing key on the handler itself, because a route with a screen is judged by app, not key level.
- **2026-11-05** — Assumed: Android SDK platform 36, not 35, because the current Flutter plugins need it.
- **2026-11-05** — Assumed: the phone app holds no server address; each device key carries it, because relay-app is public and the site's address is private.
- **2026-11-05** — Assumed: a new key shows once, as a QR code only in a terminal a person sees, and on a page readable only by the person under `~/.relay-ring/device-keys/`, so an assistant's output never holds it. A key lasts one year.
- **2026-11-05** — Assumed: the phone's database uses drift without generated code, because the four small tables do not need it.
- **2026-11-05** — Assumed: background location records each 100 m of movement on both phones, because one plugin then covers both.
- **2026-11-05** — Assumed: `ASC_KEY_P8` holds the .p8 file as base64, and `.env.example` also names `APPLE_TEAM_ID` and the Android signing values, because the iOS build signs with Apple's automatic signing and a GitHub secret is one line.
- **2026-11-05** — Assumed: relay-app's `ci.yml` tests, then calls `android.yml` and `ios.yml`; `ios.yml` skips with a notice until the App Store Connect secrets exist, so Android builds now and TestFlight waits for the paid membership.
- **2026-11-05** — Asked whether the site refuses a service key that is on no list of phones (the review found that, after a staging reset, a staging phone key counts as the preview checker) → chose refuse unknown keys: the Worker learns the checker's Client ID and refuses every other service token with no `relay_devices` row.
- **2026-11-05** — Asked how "Pin notes to a place" gets location permission, since it starts on → chose ask when the phone connects: pins stay on, and the app asks for location once, right after the phone connects.
- **2026-11-05** — Assumed: the Worker learns each checker's Client ID from a committed `RELAY_CHECKER_CLIENT_ID` var per environment in `app/wrangler.jsonc`, beside the Access audience and app id, because a Client ID opens nothing alone and the deploy has no `.env`. A new checker token needs the var changed with it.
- **2026-11-05** — Assumed: the timeline pages on the last note's time and id (`beforeId`, `nextId` beside `before`, `next`), because two notes can share a time; an older phone build that sends only `before` still works.
- **2026-11-05** — Check: `app/worker/index.test.ts` and `app/tests/runtime/runtime.test.ts` name their test service token as the checker through `RELAY_CHECKER_CLIENT_ID`, and `index.test.ts` expects the checker never to be looked up as a device. No limit or rule was loosened.
- **2026-11-05** — Assumed: `scripts/check-private-access.mjs` looks up each checker policy's token Client ID and fails the deploy when it differs from that environment's `RELAY_CHECKER_CLIENT_ID`, because a new checker key from /verify or setup would otherwise make every check fail later with a 403 that does not name the cause.
- **2026-11-05** — Save: built and reviewed twice; the review's 10 findings are fixed (tasks 7.1–7.10). Both sites hold their own `RELAY_PEBBLE_SIGNING`. Next is the live check on the preview (8.2), then the Android phone (8.3); TestFlight (8.4) waits for the paid Apple membership.
- **2026-11-05** — Assumed: `RELAY_CHECKER_SHA256` replaces `RELAY_CHECKER_CLIENT_ID`, holding the SHA-256 of each checker's Client ID, because `wiki/stack/cloudflare-access.md` keeps checker values out of git and the save's key scan stopped on the plain Client IDs. The Worker and the check before publishing hash the Client ID to compare.
- **2026-11-05** — Live check on the preview: a signed Pebble test event and a ring note were accepted, a repeat delivery counted once, a wrong signature got 401, the Pebble key got 403 outside Relay, and the note showed on the Relay page. relay-app's branch build passed and made an Android test file (debug-signed; no upload key yet).
- **2026-11-05** — Asked whether Matthew tests the real ring and the Android phone before publishing → chose publish now. Tasks 8.2 (the real ring note), 8.3 (the Android phone) and 8.4 (TestFlight, which waits for the paid Apple membership) stay open after the publish, against the live site with live keys.
- **2026-11-05** — Assumed: the three device checks leave this change's tasks as a follow-up for after the publish, because they need Matthew's ring and phones and he chose to publish now: a real ring note from the Pebble app, the Android phone (typed note, health and location sync, a ring note with its place), and TestFlight on the iPhone once the Apple membership is paid. They run against the live site with live keys made by `scripts/relay-device-key.mjs`.
- **2026-11-05** — Archive checkpoint: archived for the publish; its five capabilities are now in `openspec/specs/`.
- **2026-11-05** — The archive save's deploy stopped: CI runs `main`'s copy of `scripts/check-private-access.mjs`, which does not yet allow the "Relay devices" Access policy that the staging test keys had made. Revoked both staging test keys, which removed the policy; make new ones after this publish.
