# Design

## Context

See [proposal.md](proposal.md), *Why*. The pieces this change builds on:

- **Phone.** `mobile/lib/sync/background.dart` runs one periodic `workmanager` task (`syncTask`, one hour, network required) and `main.dart` calls `relay.sync` on resume. Each round reads health, queues location points, then `flush`es the `outbox`. `flush` sends oldest first and stops at the first upload that can't land, so order holds. `Settings` keeps `history` and `health` true only while `sending` is true. `stopSending` calls `store.dropReadings()`. `RelayApi` only posts JSON.
- **Server.** `POST attachments` is a raw `Route` that reads a note's file with `boundedBytes` and stores it with `space.files.put("attachments/<id>", bytes)`, sealed with AES-256-GCM under `people/<person id>/`. `caller.ts` `REACH.phone` lists the POST routes a phone key may call. `account-delete` calls `space.files.removeAll()`, which deletes the whole `people/<person id>/` prefix.
- **Connector.** `app/worker/relay-mcp/tools.ts` registers ten tools from `inputs.ts`: nine read `space.db` and `add_note` adds a note, each answered by `answers.ts`. `asker.ts` opens the space with `{ SPACES }` alone: *the tools read no recording, so the connector binds no file store*. `app/wrangler.relay-mcp.jsonc` and `self-host/mcp.template.jsonc` bind no R2 bucket.
- **API page.** `api-doc.ts` makes the website's route reference from each `defineAction`; a raw route gets a `HAND_PAGES` entry that points at its own page.

## Goals / Non-Goals

**Goals:**
- A photo waiting for Wi-Fi never blocks a note, a health sample or a location point.
- The server reads no photo except for its own person's page session or AI grant, by the same one door (`space.ts`) as recordings.
- A photo row holds only what the AI needs to find it: time, place, size.

**Non-Goals:**
- No server-side image work: no resize, no EXIF read, no thumbnail. The phone sends the final file.
- No change to the timeline or `day_summary`.

## Decisions

### The phone reads the library with `photo_manager`

`photo_manager` reads Apple Photos and Android's MediaStore with one API: assets filtered by `createDateTime`, each asset's `latitude`/`longitude` (Android needs `ACCESS_MEDIA_LOCATION`), and `thumbnailDataWithSize(ThumbnailSize(1600, 1600), format: jpeg, quality: 80)`, which renders a new JPEG with no EXIF block. The position therefore travels only as the upload's own fields. *Alternative:* `image_picker` covers one pick at a time, not new photos in the background; a native plugin per platform doubles the work.

On turn-on, the app stores `photosSince = now` in `state`. Each round asks for images with `createDateTime > photosAfter` (the newest one queued so far, starting at `photosSince`), oldest first, at most 50 a round. Videos are skipped; screenshots and Live Photos go as still images. An iCloud-only asset is fetched by `photo_manager` with network access allowed, only on Wi-Fi or when mobile data is allowed.

### Photos get their own queue, not the outbox

A new `photos` table on the phone (schema version 5): `client_id` (UUID), `asset_id`, `taken_at`, `lat`, `lon`, `width`, `height`, `path` (the JPEG in the app's support folder), `created_at`. The round copies new assets into it, then, after the outbox `flush`, sends the queue oldest first when `connectivity_plus` reports Wi-Fi (or any network with `photosOnMobileData`). A refused body (400/413) is dropped like an outbox item; an offline answer stops the photo send only. *Alternative:* an outbox item per photo would stop `flush` at the first photo waiting for Wi-Fi and hold every later note, as `flush` keeps order.

Turning *Photos* off, or `stopSending`, deletes the queue rows and their files and clears `photosAfter`, so a later turn-on starts again from that moment.

### `POST photos` is a multipart raw route, like `POST pebble`

Fields: `clientId`, `takenAt` (ms), optional `lat`, `lon`, and `photo` (`image/jpeg`, at most 3 MB, checked with `boundedBytes`; the JPEG's own size is read from its SOF marker, and a long side over 1,600 px or a non-JPEG is refused with 400). The route is `asDevice` and joins `REACH.phone`. It inserts into `relay_photos` with `ON CONFLICT (device_id, client_id) DO NOTHING`; only a new row seals and puts the file, under `people/<person id>/photos/<photo id>`. It answers `{ ok: true, added: 0|1 }`. *Alternative:* base64 inside JSON costs a third more bytes and the 256 KB JSON limit.

A photo's item is `photos/<id>`: `space.ts` `filesOf` names it with `nameOf`, as a note's file is `attachments/<id>`, so photos, files and recordings share the seal and the prefix check. `removeAll` already covers all three.

### The space table

`schema/space-migrations/0007_photos.sql`:

```sql
CREATE TABLE relay_photos (
  id TEXT PRIMARY KEY, device_id TEXT NOT NULL, client_id TEXT NOT NULL,
  taken_at INTEGER NOT NULL, lat REAL, lon REAL, width INTEGER NOT NULL, height INTEGER NOT NULL,
  bytes INTEGER NOT NULL, file_key TEXT NOT NULL, created_at INTEGER NOT NULL,
  UNIQUE (device_id, client_id)
);
CREATE INDEX relay_photos_taken ON relay_photos (taken_at, id);
```

### The page: `GET photos` and `POST photos/delete`

Both are `defineAction`s behind `asPerson`, so a key is refused by `reaches` (its regex is anchored at `photos$`) and by `asPerson`. `GET photos` answers `{ count }`. `POST photos/delete` takes `{ confirm: "delete" }`, lists `relay_photos.file_key` a page at a time, deletes those objects, then the rows, and answers `{ deleted }`. Recordings under the same prefix stay. A new `Photos.tsx` card sits above `<Devices />` on the page.

### Two connector tools

- `photos`: `from`, `to`, optional `near: { lat, lon, km ≤ 500 }`, `limit ≤ 50`, `cursor`, `timezone`. It answers `{ id, takenAt, lat, lon, width, height }` rows, newest first, and `nextCursor` in the same `<ms>.<id>` shape as notes. *Near* filters by a bounding box in SQL, then by haversine distance in code.
- `read_photo`: `id` → `{ content: [{ type: "image", data: <base64>, mimeType: "image/jpeg" }, { type: "text", text: <time and place> }] }`. A missing id is a tool error.

The connector's `asker.ts` opens the space with `{ SPACES, RELAY_BUCKET }`, and `answers.ts` answers `read_photo` from the asker's whole space, not only its `db`, so it reads through `space.files.open`. Both tools sit in `inputs.ts` beside the other tools; the web API has no photo route, because `read_photo` answers an image and `near` is no query field. `app/wrangler.relay-mcp.jsonc` (each env) and `self-host/mcp.template.jsonc` bind the same bucket as the app. The `tool` wrapper learns to pass an image answer through. The read-only test keeps checking that every tool is `readOnlyHint` and that the connector runs no write SQL.

### Docs and wiki

The website gets `app/photos.md` and the menu entry; `privacy.md`, `app/settings.md` and `connections/connect-your-ai.md` add photos; `api-doc.ts` adds a `HAND_PAGES` entry for `POST photos` pointing at `../../app/photos/#what-the-phone-sends`, and `npm run relay:api-doc` rewrites `api/reference.md`. `wiki/relay-spaces.md` *Recordings* becomes *Recordings and photos*.

## UX

### Use-case brief
One person who already sends notes, health or location from the phone app turns photos on once in Settings, then forgets it: photos arrive in their space as they take them. Done looks like: later, they ask their AI about a trip and it finds the photos. Context: on the phone, once; the page's photo card is seen now and then, and *Delete all photos* is rare. The common case is Wi-Fi at home; the edge cases are mobile data, *Limited* access on iPhone, and access denied. The Settings rows mirror the existing *Health* and *Location history* switches; the page card mirrors the *Devices* card.

### Flow
Settings → *Photos* on → the system's photo-access prompt → on. Denied → the switch stays off and a snackbar says *Photo access is off. Turn it on in the phone's Settings.*, as health does. Off → a dialog: *Stop sending photos? Photos already sent stay on your Relay Everything server. Delete them on your page.* with *Open my page* and *Stop sending photos*. Page → *Delete all photos* → confirm dialog → the count reads *No photos yet*.

### Hierarchy
- Settings: the *Photos* switch is the one action; *Send photos on mobile data* is enabled only while *Photos* is on.
- Page card: the count is the content; *Delete all photos* is the one action, styled destructive and outlined, not filled.

### Review
[review.html](review.html). The *Photos* switch item sketches the Settings screen; the page item sketches the photo card.

### Components
Phone: `SwitchListTile`, `AlertDialog` and `SnackBar`, as in `screens/settings.dart`. Page: `Card`, `Button variant="destructive"` and `Dialog`, as in `Account.tsx`. Nothing new.

### Photos go to a webhook as one `photo.created` each

The `photos` kind gets a webhook part, marked `sensitive`, so a new webhook does not take it until the person ticks it. A trigger on `relay_photos` logs each new row in `relay_outbox`, as the other kinds do. Because `relay_outbox` lists its kinds in a `CHECK`, the photos migration rebuilds the table and keeps every row, place and trigger, as main's note-files migration does; one migration holds all of photos, so a renumber moves one file. `POST photos` wakes the sender after it stores the file.

The builder reads the photo row and its sealed file, and answers `photo.created` with the JPEG in base64. The row is written before the file, so a missing file waits a short time, then the entry is skipped; a deleted photo is skipped. A kind marked `alone` goes one log entry per message, so a message never holds more than one photo. *Alternative:* a link to fetch the photo keeps messages small, but needs a new route that reads with a webhook's secret, and a phone with no server has no such route.

On the phone, `WebhookClient` gets `sendPhoto`, so `sendPhotos` works for both places through `Outbound`. It signs a format v1 `photo.created` with the same shape, and its `webhook-id` holds the photo's id, so a resend keeps its id and body. Photos keep their own queue, so a photo the receiver refuses does not hold back notes. A `413` drops the photo.

## Risks / Trade-offs

- [iOS runs background work when it likes] → the app also runs a round on every open; the website page says photos can arrive hours late.
- [A large photo burst on mobile data allowed] → 50 photos a round at about 300 KB each is about 15 MB an hour at most.
- [MCP clients differ on image results] → `read_photo` also answers a text line with the time and place, so a client that drops images still gets something; the Claude apps show the image.
- [Photo GPS is private] → it stays in the person's sealed space, goes only to a webhook the person ticked for *Photos* or set on the phone, and the privacy page says photos carry their place.
- [A photo is a large webhook body] → one photo a message, at most about 4 MB in base64, under the 16 MB the docs tell a receiver to accept.
- [App Store review asks why the app reads photos] → `NSPhotoLibraryUsageDescription` says it sends new photos to the person's own server only when they turn it on.

## Migration Plan

The space migration runs in each space's constructor on first use, so no step runs by hand. Deploy order stays as in [the spaces wiki page](../../../wiki/relay-spaces.md#the-workers-and-their-order); the connector now also needs the bucket binding. Phones need the new app build; an old build never calls `POST photos`. Rollback: the table and an empty `photos/` prefix are harmless if the routes go away.
