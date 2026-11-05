# Design

## Context

Relay runs on WongStack (Artifacts route). The site's Worker sits behind Cloudflare Access; `app/worker/access.ts` reads a service token's Client ID as `{ kind: "service" }`, and mini apps get `identity` in their handlers. `mobile/` holds only a README and is copied to the public `matthewwong525/relay-app` by `scripts/publish-relay-app.mjs` after each publish. Pebble's app (coredevices/mobileapp, `experimental/.../indexwebhook/INDEX_WEBHOOK_API.md`) posts version-1 multipart webhooks: `audio` (m4a, 16 kHz), `transcription`, `recordedAt` (ms), `client=ring`, headers `X-Index-Delivery`, `X-Index-Trigger`, `X-Index-Timestamp`, `X-Index-Signature` (HMAC-SHA256 over `"v1\n{ts}\n{delivery}\n{trigger}\n{test?1:0}\n" || body`), plus any custom headers, and retries 408/429/5xx for up to 10 minutes.

## Goals / Non-Goals

**Goals:** a server-side Relay mini app storing notes, health and location; device keys; a Flutter app for iOS and Android; automatic builds in relay-app.

**Non-Goals:** BLE to the Relay ring, watch apps, outbound webhooks, MCP, docs site, multi-user accounts, an open-source server.

## Decisions

### Server: a mini app named `relay`

- `app/worker/apps/relay/api.ts` routes, each in its own handler file:
  - `POST pebble`: verify version, timestamp (±300 s), signature with the saved key `relay-pebble-signing`, then dedupe on `X-Index-Delivery`. A test event (`X-Index-Test: true`) is verified and answered 200 but not stored.
  - `POST notes`: a typed note `{ clientId, text, createdAt, lat?, lon?, accuracy? }`, idempotent on `(device, clientId)`.
  - `POST health`: a batch of `{ type, start, end, value, unit, source }`, idempotent on `(device, type, start, end, source)`.
  - `POST locations`: a batch of `{ at, lat, lon, accuracy }`, idempotent on `(device, at)`.
  - `GET timeline?before=&beforeId=&limit=`: notes with resolved place, newest first, paged on the last note's time and id (`next`, `nextId`), so two notes at one time are never skipped.
  - `GET summary?day=`: counts, health totals and places for the site page. Steps and sleep take the largest source on one device, then the largest device, so an iPhone and its Apple Watch don't double a day.
  - `GET audio?id=`: streams the m4a from R2, and answers one `Range` with 206 and `Content-Range`, as Safari asks for one before it plays.
- Tables, from one migration in `schema/migrations/`: `relay_devices(id, name, token_client_id unique, created_at, revoked_at)`, `relay_notes(id, device_id, source 'ring'|'typed', delivery_id unique, client_id, text, audio_key, recorded_at, lat, lon, accuracy, place_from 'phone'|'history'|null)`, `relay_health(..., unique(device_id, type, start, end, source))`, `relay_locations(..., unique(device_id, at))`. Batches are capped (500 rows) and validated with the shared contract.
- Ring-note place: at insert, the nearest `relay_locations` point within 10 minutes; a later location batch fills places for notes still without one in its window.
- Audio goes to R2 `RELAY_BUCKET` (`relay-ring-notes`, staging `relay-ring-notes-staging`) at `notes/<id>.m4a`; the body is capped at 10 MB.
- Seed rows for each table in `schema/seed.sql` (made-up Toronto places, no real data).

### Device keys

- One Cloudflare Access service token per device (`relay-ring device <name>`), added to a dedicated machine policy `Relay devices` on the production Access app (staging gets its own token and policy for previews).
- `scripts/relay-device-key.mjs create|list|revoke --name <device> [--staging]` uses the user token from `.env`: it creates the token, adds it to the policy, and records its Client ID in `relay_devices` through the D1 API. The secret is printed once, as a QR code in the terminal and as text in a private hand-over page, never logged or committed.
- The Worker allows a `kind: "service"` caller whose Client ID is an unrevoked row in `relay_devices` to reach only `/apps/relay/api/{pebble,notes,health,locations,timeline}` (and the audio route); anything else refuses it. If the core app-permission check refuses unknown service tokens before the mini app runs, this change adds a narrow, tested exception for Relay device tokens there.
- The Worker refuses every other service token except the checker. Each environment's committed `RELAY_CHECKER_SHA256` var in `app/wrangler.jsonc` holds the SHA-256 of its checker's Client ID: the live checker (`CF_ACCESS_CLIENT_ID`) in production, the preview checker (`CF_ACCESS_STAGING_CLIENT_ID`) in staging. Git keeps only the fingerprint, because checker values stay out of git; the Worker hashes each service token's Client ID to compare. Without this, a staging phone's key that a staging reset took off the list would count as the checker, own all of staging, and be out of reach of `revoke`. A new checker token needs the var changed with it: `scripts/check-private-access.mjs` reads each checker policy's token Client ID and stops the publish with a message that names `RELAY_CHECKER_SHA256`, the file and the new fingerprint when they differ. The CI deploy key may read policies but not service tokens, so there the result says `checkerKey: unverified`, and a preview from this computer, with the user token, makes the full check.
- Pebble's webhook sends the Pebble device's `CF-Access-Client-Id` and `CF-Access-Client-Secret` as custom headers, plus signs with the separate signing secret.

### Site page: `app/src/apps/relay/`

`App.tsx` with `app.json`: summary tiles, the timeline (play audio inline), places list, and two dialogs: *Set up a phone* (the command to run and where the key appears) and *Pebble webhook* (the URL, which custom headers to add, signing on, Transcription + Recording). Links to the latest relay-app release and the TestFlight invite.

### Phone app: Flutter in `mobile/`

- `flutter create --org com.matthewwong525 --project-name relay_app --platforms ios,android .`; Dart only, packages under permissive licences.
- Local store: `drift` (SQLite) holding notes, pending uploads and the timeline cache; an outbox sends in order and marks rows sent.
- Health: the `health` package (HealthKit / Health Connect): steps, heart rate, sleep sessions, workouts; read since the last synced time; on open and every hour via `workmanager` (Android) and background fetch (iOS, best effort).
- Location: `geolocator` for the note's pin; background history with significant-change updates on iOS and a 100 m distance filter with a foreground-service notification on Android. *Pin notes to a place* starts on, so the app asks for location once, right after the phone connects; the history asks when it is turned on. A note is kept at once and its pin follows when the phone has a fix.
- Health on Android also asks for Health Connect's background read, which the hourly sync needs.
- Key entry: scan the QR or paste; the key lives in `flutter_secure_storage` (Keychain/Keystore). Server URL defaults to production, editable for previews.
- Structure: `lib/data/` (store, api client, outbox), `lib/sync/` (health, location), `lib/screens/` (timeline, compose, settings, connect), with unit tests for the outbox, parsers and dedupe, and widget tests for each screen.

### Builds in relay-app

`mobile/.github/workflows/` (copied to relay-app's root by the mirror):
- `ci.yml` on every push: `flutter analyze` and `flutter test`.
- `android.yml` after CI: `flutter build apk --release` signed with an upload keystore kept in GitHub secrets; artifact on branches, release asset on `main`.
- `ios.yml` after CI, on `macos-latest`: fastlane with the App Store Connect API key (`ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`) and automatic signing, then `upload_to_testflight`, build number from the run number.
- The keys reach GitHub with `gh secret set` on stdin from `.env`, which gets their blank names in `.env.example`.

### Mirror changes

`scripts/publish-relay-app.mjs` adds `.p8`, `.cer`, `.certSigningRequest` and `.provisionprofile` to the refused files, and `--branch <name>` to push a non-`main` branch (no default-branch change). Tests cover both.

### This computer

Flutter stable, Android command-line tools (platform 35, build-tools), and OpenJDK 17, installed under `/opt` or `~/.local` with `sudo -n apt` where needed.

## UX

**Brief.** Matthew, building Relay, wants a thought saved within seconds wherever he is: walking, driving, at the bench. Done is the note visible in the timeline, with its place, on both phones and the site. The ring is the common case (many times a day); typing on the phone is the fallback; the site is for review, a few times a week. Assumed: one person, two phones, one ring.

**Shortest flow.** Ring: hold, talk, release → it appears in the timeline on the next sync. Phone: open → *New note* → type → *Save* (the keyboard opens at once; the note shows at once and its place follows). First open: *Scan the QR code* → the phone asks for location once, for pins.

**Hierarchy.** Timeline: *New note* is the one primary action. Settings: none primary; each toggle acts at once. Site page: no primary action; two setup dialogs as ghost buttons. Mirrors the site's Inbox page for the list and Access for the setup dialogs.

**Components.** Phone: Material 3 list cards with a source tag and a muted time-and-place line; a floating *New note* button; a sync chip; switches in Settings. Site: `Card`, `Button`, `Badge` and `Dialog` from `app/src/components/ui/`.

### Review

[review.html](review.html) sketches the timeline (What Changes item 2), Settings (item 3) and the site page (item 4).

## Risks / Trade-offs

- **Service tokens through the core permission check** may need a core edit; it stays narrow and tested, and the deployment check must still pass.
- **iOS background limits**: health and location in the background are best effort; opening the app always syncs.
- **Android 14 foreground-service rules** make background location show a persistent notification; that is the cost of continuous history.
- **Health and location are sensitive.** They stay in Matthew's Cloudflare account and never enter memory, the wiki or relay-app.
- **TestFlight** needs a paid Apple Developer account and the first build's export compliance answer in App Store Connect.
