# Send photos from the phone to Relay Everything, for your AI to see

**Status:** planned
**Branch:** shy-bedbug
**Open questions:** none

## Why

Your AI can't see the photos on your phone. iCloud Photos has no way in for other apps, and Google Photos stopped letting apps read a whole library in 2025. Only an app on the phone can read them. Relay Everything already passes on what your AI can't reach (notes, health, places), so photos fit: the phone sends them, and your AI reads them through the connector, with no captions or tags added.

## What Changes

- **A new *Photos* switch in Settings, off by default.** It sits under *Send to Relay Everything*, beside health and location, and works only while sending is on. Turning it on asks for photo access. A second switch, off by default, lets photos go over mobile data. Without it, photos wait for Wi-Fi.
  ```screen
  <div class="card col gap phone">
    <h3>Settings</h3>
    <div class="row gap"><div class="col grow"><b>Send to Relay Everything</b><span class="muted">Off: nothing leaves this phone.</span></div><span class="tag">On</span></div>
    <div class="row gap"><div class="col grow"><b>Health: steps, heart rate, sleep, workouts</b><span class="muted">Sends them every hour.</span></div><span class="tag-outline">Off</span></div>
    <div class="row gap"><div class="col grow"><b>Location history</b><span class="muted">Keeps a point each 100 m you move.</span></div><span class="tag">On</span></div>
    <div class="row gap"><div class="col grow"><b>Photos</b><span class="muted">Sends new photos, with when and where you took them, so your AI can see them.</span></div><span class="tag">On</span></div>
    <div class="row gap"><div class="col grow"><b>Send photos on mobile data</b><span class="muted">Off: photos wait for Wi-Fi.</span></div><span class="tag-outline">Off</span></div>
  </div>
  ```
  A sketch: the phone app is the Flutter app, which the prototype can't run.
- **Only new photos go, from the time you turn it on.** The phone doesn't send your old library. About once an hour, and each time you open the app, it finds the photos taken since the last check. It sends a smaller copy of each, about 1,600 pixels on the long side, which is the most an AI uses. Each photo keeps when and where it was taken. On iPhone, iOS decides when background work runs, so a photo can arrive some hours late.
  ```mermaid
  flowchart TD
    T["New photo"] --> R["Hourly, or app opens"]
    R --> S["Small copy, time, place"]
    S --> W{"Wi-Fi?"}
    W -->|yes| U["Your space"]
    W -->|no| Q["Waits"]
    Q --> W
  ```
- **Each photo is locked in your own space.** The server keeps each photo in your own folder, locked with your space's own key, the same as a ring recording. Only you, through your page or your AI app, can get to it. Your phone's key can only add photos. It can't read or delete them.
- **Your AI can find and look at your photos.** The connector gets two new read-only tools. One lists photos in a time range, with a choice to look only near a place. The other gives your AI one photo to look at. For example: *show me the photos from the trip to Lisbon*.
- **Your Relay Everything page shows how many photos you sent, and can delete them all.** You get a count and a *Delete all photos* button, with no photo grid. Turning photos off on the phone stops sending and says where to delete the photos already sent. Deleting photos can't be undone.
  ```screen
  <div class="card col gap phone">
    <h3>Photos</h3>
    <p>312 photos sent from your phones.</p>
    <p class="muted">Your AI can see them. Turn photos off in the phone app's Settings.</p>
    <div class="row gap"><button class="btn-ghost danger">Delete all photos</button></div>
  </div>
  ```
- **The website explains photos.** A new *Photos* page under *Use the app*. The privacy page says photos carry when and where you took them. The settings, AI and API pages list the new switch, tools and routes.

Non-goals: sending the old library, videos, sending photos to webhooks, captions or tags or text read from photos, a photo grid on the page, and deleting photos from the phone.

## What the build needs

- **Nothing.** No new key or account. The phone asks for photo access itself, and the server uses the file store it already has.

## Capabilities

### New Capabilities
- `relay-photos`: the phone's *Photos* switch and what it sends; storing each photo sealed in the person's space; the page's count and *Delete all photos*.

### Modified Capabilities
- `relay-ai-connector`: the tools also read chats and photos, and one tool returns one photo as an image; recordings still never go out.
- `relay-device-keys`: a phone key may add photos, and may not list, read or delete them.

## Impact

- `mobile/`: `pubspec.yaml` adds `photo_manager` and `connectivity_plus`; `lib/data/settings.dart` (`photos`, `photosOnMobileData`); `lib/data/store.dart` (schema version 5, a `photos` queue table); new `lib/sync/photos.dart`; `lib/sync/background.dart`, `lib/controller.dart`, `lib/relay.dart` and `lib/screens/settings.dart`; `lib/data/api.dart` gains a multipart upload. `ios/Runner/Info.plist` adds `NSPhotoLibraryUsageDescription`; `android/app/src/main/AndroidManifest.xml` adds `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (API ≤ 32) and `ACCESS_MEDIA_LOCATION`.
- `schema/space-migrations/0003_photos.sql`: a new `relay_photos` table in each space.
- `app/worker/apps/relay/`: new `photos.ts` (`POST photos`, `GET photos`, `POST photos/delete`); `api.ts` routes; `caller.ts` phone reach adds `photos`; `space.ts` file names for photos; `queries.ts` photo reads; `account.ts` delete text.
- `app/worker/relay-mcp/tools.ts`: `photos` and `read_photo` tools; `index.ts`/`tools.ts` pass the file store; `app/wrangler.relay-mcp.jsonc` and `self-host/mcp.template.jsonc` bind `RELAY_BUCKET`.
- `app/src/apps/relay/`: new `Photos.tsx` card; `Account.tsx` delete text.
- Website: new `site/src/content/docs/app/photos.md`, `site/sidebar.mjs`, `privacy.md`, `app/settings.md`, `connections/connect-your-ai.md`, `api/reference.md` from `npm run relay:api-doc`.
- Wiki: `wiki/relay-spaces.md` (photos beside recordings), `wiki/stack/relay-ai-connector.md` (the file store binding).
- `scripts/product-name.test.mjs`: the new user-facing files join its list.

## Decision log

- **2026-11-06** — Asked whether Relay Everything should summarize, tag or link data → chose no: it only relays raw data, and the AI does the rest through the connector.
- **2026-11-06** — Asked whether to send photos → chose yes, with a switch the person turns on or off, like health and location.
- **2026-11-06** — Asked how new photos get sent → chose the existing hourly background round, plus each time the app opens.
- **2026-11-06** — Asked whether to keep the GPS position → chose to keep it, as its own fields, so the AI can find photos by place.
- **2026-11-06** — Asked where a person deletes photos already sent → chose a *Delete all photos* button on the Relay Everything page, so phone keys stay add-only.
- **2026-11-06** — Asked whether the page shows the photos → chose only a count and the delete button.
- **2026-11-06** — Assumed: only photos taken after the switch turns on go, with no old library, because a whole library is thousands of large files and photos the person never meant to share.
- **2026-11-06** — Assumed: the phone sends a copy about 1,600 pixels on the long side, JPEG, not the original, because that is the most an AI uses and it keeps storage small.
- **2026-11-06** — Assumed: photos wait for Wi-Fi unless the person turns on *Send photos on mobile data*, because photos are much larger than notes or health data.
- **2026-11-06** — Assumed: photos wait in their own queue on the phone, not the shared outbox, because the outbox stops at the first upload that can't go, so a photo waiting for Wi-Fi would hold back every note.
- **2026-11-06** — Assumed: photos go to no webhook, because webhooks send small JSON rows, and the plan keeps to the AI connector.
- **2026-11-06** — Assumed: turning photos off, or turning sending off, deletes the photos still waiting on the phone and stops reading the library, as health and location do.
- **2026-11-06** — Assumed: on iPhone, *Limited* photo access sends only the photos the person picked for the app, because iOS shows the app no others.
- **2026-11-06** — Assumed: the connector's photo list holds at most 50 photos a page, and `read_photo` returns one photo per call, because one photo as an image is up to about half a megabyte.
- **2026-11-06** — Assumed: the place filter is a point and a distance in kilometres, because the AI can get a point from `places` or its own knowledge, and the server does no place lookup.
- **2026-11-07** — Assumed: *Delete all photos* sends `{ confirm: "delete" }` and deletes a page of photos at a time, files first, then rows, so a failed step leaves no row without its file.
- **2026-11-07** — Assumed: the place filter uses a box in SQL that wraps the date line and covers the whole circle near a pole, then an exact distance in code.
- **2026-11-07** — Assumed: the page hides *Delete all photos* while it holds no photos.
- **2026-11-07** — Assumed: Android 14 also asks for `READ_MEDIA_VISUAL_USER_SELECTED`, so a person can give access to some photos only, as on iPhone.
- **2026-11-07** — Assumed: the phone keeps the ids it sent in the last second, so two photos taken in the same second are neither sent twice nor missed.
- **2026-11-07** — Assumed: photos go only after a round's notes, health and places went with no failure, and a photo upload waits up to 120 seconds, because a photo is larger than any other upload.
- **2026-11-07** — Assumed: `connectivity_plus` stays at 7.3.1, because 7.3.2 needs a newer `dbus` than `geolocator` 14 allows, and the packages would not resolve.
- **2026-11-07** — Assumed: the phone names `http_parser` as its own package, because the photo upload sets its content type with it, and it was already there through `http`.
- **2026-11-07** — Assumed: when a server refuses a photo upload, as an older self-hosted server does, the phone stops only the photo send and does not show *Key refused*, because notes still go and the key is fine.
- **2026-11-07** — Assumed: when a photo's copy fails, as with an iCloud download cut short, the round stops at that photo and the next round tries it again; after 3 failed rounds the phone skips it, so one broken photo can't stop the rest.
