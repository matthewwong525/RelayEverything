# Send photos from the phone to Relay Everything, for your AI to see

**Status:** in-progress
**Branch:** relay-feature-ideas
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
- **Photos can go to your own webhook too.** On the server, each new photo goes to the webhooks you tick for *Photos*, which is a sensitive tick, like health and location. With no account, a phone that sends straight to your own webhook sends each new photo there itself. Each message holds the photo, when and where you took it, and its size.
- **The website explains photos.** A new *Photos* page under *Use the app*. The privacy page says photos carry when and where you took them. The settings, AI and API pages list the new switch, tools and routes.

Non-goals: sending the old library, videos, captions or tags or text read from photos, a photo grid on the page, and deleting photos from the phone.

## What the build needs

- **Nothing.** No new key or account. The phone asks for photo access itself, and the server uses the file store it already has.

## Capabilities

### New Capabilities
- `relay-photos`: the phone's *Photos* switch and what it sends; storing each photo sealed in the person's space; the page's count and *Delete all photos*.

### Modified Capabilities
- `relay-ai-connector`: the tools also read chats and photos, and one tool returns one photo as an image; recordings still never go out.
- `relay-device-keys`: a phone key may add photos, and may not list, read or delete them.
- `relay-webhooks`: photos go to a webhook ticked for them, one photo a message; only files and chats still have no webhook message.
- `relay-phone-webhook`: a phone that sends to its own webhook sends new photos there too, apart from its notes.

## Impact

- `mobile/`: `pubspec.yaml` adds `photo_manager` and `connectivity_plus`; `lib/data/settings.dart` (`photos`, `photosOnMobileData`); `lib/data/store.dart` (schema version 5, a `photos` queue table); new `lib/sync/photos.dart`; `lib/sync/background.dart`, `lib/controller.dart`, `lib/relay.dart` and `lib/screens/settings.dart`; `lib/data/api.dart` gains a multipart upload. `ios/Runner/Info.plist` adds `NSPhotoLibraryUsageDescription`; `android/app/src/main/AndroidManifest.xml` adds `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (API ≤ 32) and `ACCESS_MEDIA_LOCATION`.
- `schema/space-migrations/0008_photos.sql`: a new `relay_photos` table in each space.
- `app/worker/apps/relay/`: new `photos.ts` (`POST photos`, `GET photos`, `POST photos/delete`); `api.ts` routes; `caller.ts` phone reach adds `photos`; `space.ts` file names for photos; `queries.ts` photo reads; `account.ts` delete text.
- `app/worker/relay-mcp/tools.ts`: `photos` and `read_photo` tools; `index.ts`/`tools.ts` pass the file store; `app/wrangler.relay-mcp.jsonc` and `self-host/mcp.template.jsonc` bind `RELAY_BUCKET`.
- `app/src/apps/relay/`: new `Photos.tsx` card; `Account.tsx` delete text.
- Website: new `site/src/content/docs/app/photos.md`, `site/sidebar.mjs`, `privacy.md`, `app/settings.md`, `connections/connect-your-ai.md`, `api/reference.md` from `npm run relay:api-doc`.
- Wiki: `wiki/relay-spaces.md` (photos beside recordings), `wiki/stack/relay-ai-connector.md` (the file store binding).
- `scripts/product-name.test.mjs`: the new user-facing files join its list.
- Photos to webhooks: the photos migration also rebuilds `relay_outbox` with the `photo` kind and logs each photo; `kinds.ts`, `webhooks/format.ts` and `webhooks/send.ts` build and send `photo.created`; `photos.ts` wakes the sender; the phone's `data/webhook.dart` and `sync/photos.dart` send it; `site/public/webhooks/receiver.mjs`, `v1.schema.json` and `connections/your-database.md` describe it.

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
- **2026-11-07** — Assumed: after Apple Health and location began to wake the closed iPhone app, the photo step runs in each wake's round too, last, because a wake runs the same round as the hourly task; a wake that iOS ends at 25 s has sent the readings and points first, and a photo it did not send waits for the next round.
- **2026-11-07** — Saved for final acceptance: built, reviewed twice, merged with the iPhone health, places and connect change (#27), and the local checks pass; the staging check (6.2) and the phone build check (6.3) remain.
- **2026-11-07** — Asked: Matthew said build and ship, after a recap that named bringing in main, adding photos to the data kinds list, hiding *Photos* in phone-webhook mode, and keeping shared photos and photo sending apart in the docs; these are tasks 6.1–6.4, and the checks move to 7.
- **2026-11-07** — Assumed: when the phone sends straight to one webhook, *Photos* hides and sends nothing, because photos carry their place and go to no webhook.
- **2026-11-07** — Assumed: the photo migration is `0007_photos.sql`, after main's `0003_api_devices` to `0006_phone_data`, because the second change to publish renumbers.
- **2026-11-07** — Assumed: a photo's file name comes from main's `nameOf("photos/<id>")`, as a note's file does, so `photoName` goes and `put` takes an item, not a full name.
- **2026-11-07** — Assumed: the `photos` and `read_photo` tools move into main's `inputs.ts` and `answers.ts`, and the web API gets no photo route: `read_photo` answers an image, which the web API does not send, and `near` is no query field. The data kinds list names the two tools and `app/photos`, and lists the API part as missing with that reason.
- **2026-11-07** — Assumed: the data kinds list keeps photos' webhook part missing for good, because each photo carries its place; a photo shared into a note goes as one of the note's files.
- **2026-11-07** — Assumed: when the phone sends to a webhook, Settings reads photos as off. A move to the webhook drops the photos still waiting on the phone, as turning photos off does, and turning photos on there gives *Photos go only to Relay Everything. They do not go to a webhook.*
- **2026-11-07** — Assumed: the phone's photo queue is store schema version 7, after main's files table (5) and calendar table (6).
- **2026-11-07** — Assumed: Android keeps `READ_MEDIA_IMAGES` and `READ_EXTERNAL_STORAGE` up to Android 12, which main's file opener had removed, because *Photos* needs them. Video and audio stay removed.
- **2026-11-07** — Assumed: iOS has one `NSPhotoLibraryUsageDescription` that covers both photos picked for a note and *Photos* sending.
- **2026-11-07** — Assumed: the photo upload call on the phone is `RelayApi.multipart`, because main's `RelayApi.upload` already sends note files.
- **2026-11-07** — Saved after bringing in main: the 48 overlapping files are resolved with main's designs kept, photos are a data kind with no webhook, *Photos* hides in phone-webhook mode, and the Privacy page limits its no-webhook lines to the *Photos* switch, because a photo shared into a note is a note's file; the staging check (7.2) and the phone build check (7.3) remain.
- **2026-11-07** — Staging check (7.2) passed on `app-staging.relayeverything.com` with the branch's spaces Worker, connector and shared server deployed by hand: a phone key sent a test photo once (a resend added none), the key could not read the count, the page count read 1, the connector's `photos` found it by place and `read_photo` gave back the JPEG and its text line, *Delete all photos* left 0, and the key off was refused.
- **2026-11-07** — Assumed: the connector's consent page names calendar and photos among what an AI app can read, because the staging check showed it still read *notes, health, places and saved chats*.
- **2026-11-08** — Asked: Matthew said photos should also go to a webhook, because a webhook is his own secured place. He chose both ways, ticked: with no account the phone sends new photos straight to its webhook, and on the server photos go only to webhooks ticked for *Photos*, marked sensitive, each message holding the photo and its time and place. This replaces the earlier no-webhook decisions; tasks 7.1–7.3 and 8.4 carry it, and the checks move to 8.
- **2026-11-08** — Assumed: the photo log trigger goes in the photos migration, not a migration of its own, because main's note files take the next number and the photos migration is renumbered anyway. It rebuilds `relay_outbox` to allow `photo`, and keeps every log entry and webhook place.
- **2026-11-08** — Assumed: each `photo.created` holds one photo, because a photo is up to 3 MB, about 4 MB in base64. The server waits for a photo's file a short time, because the row is stored before the file; a photo deleted since, or whose file never came, is skipped.
- **2026-11-08** — Assumed: a photo's `place` has only `lat` and `lon`, with no place name, because the server does no place lookup. The phone's message uses the phone's own id for the photo, and its `timestamp` is when the phone queued it, so a resend has the same body.
- **2026-11-08** — Assumed: photos waiting on the phone follow a move between Relay Everything and the person's own webhook, as notes do, and go to the new place.
- **2026-11-08** — Assumed: a photo the webhook refuses with `413` is dropped, and Settings does not name it, because a photo has no name the person gave it.
- **2026-11-08** — Assumed: with the person's own webhook, turning *Photos* off shows no question about the page, because no photo is on a Relay Everything page.
- **2026-11-08** — Assumed: the webhook tick reads *Photos: each with the picture, when and where you took it*, as the other ticks name what they send.
- **2026-11-08** — Assumed: after main's note files (`0007_note_files.sql`), the photo migration is `0008_photos.sql`. Its outbox rebuild allows `note.file` too and makes main's `relay_outbox_note_file` trigger again, and each step is safe to run again, because a staging space ran it once as `0007_photos`.
- **2026-11-08** — Assumed: `photo.created` takes main's `WithFile` shape, with `base64` empty, so the sender writes the photo's bytes into the body as it does a note's file, and a `413` skips the photo. The card names it as *the photo taken <date and time> UTC*, because a photo has no name. The `alone` flag in `kinds.ts` stays the one grouping rule, and Notes, with `note.file`, is marked `alone`.
- **2026-11-08** — Assumed: on main's new Settings screen, *Photos* and *Send photos on mobile data* sit in the *Sending* group after *Location history*, and *Stop sending?* says photos stop with either place, because photos now go to a webhook too.
- **2026-11-08** — Assumed: main's `0007_note_files.sql` stays as shipped, because the first `0007_photos` that staging ran never touched the outbox; the test fixture is that deployed file.
