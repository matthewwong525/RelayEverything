# Tasks

## 1. Space and server

- [x] 1.1 Add `schema/space-migrations/0007_photos.sql` with `relay_photos` and its index, by the design; extend `space-schema.test.ts` so a new space holds `relay_photos` and D1 does not
- [x] 1.2 In `app/worker/apps/relay/space.ts`, add `photoName(id)` under `people/<person id>/photos/` and let `put` take a name; `space-access.test.ts` and the recording tests still pass, and a new test shows a photo sealed under one name fails to open under another
- [x] 1.3 Add `photos.ts` with `POST photos` (multipart, `asDevice`, JPEG only, at most 3 MB and 1,600 px long side, once per device and `clientId`), `GET photos` (`{ count }`) and `POST photos/delete` (`asPerson`, deletes photo files and rows, keeps recordings); register them in `api.ts`, add `photos` to `REACH.phone` in `caller.ts`; tests in `photos.test.ts`: a resend adds 0, a PNG or 2,000 px JPEG gets 400, a phone key gets 403 on `GET photos` and `POST photos/delete`, Ana's session never counts or deletes Ben's photos, and delete keeps a ring recording
- [x] 1.4 Add the photo reads to `queries.ts` (page by `taken_at` and id, optional bounding box) with tests for paging and the place filter; extend `isolation.test.ts` so Ana's queries never return Ben's photos
- [x] 1.5 Update `account.ts`'s delete text and `Account.tsx`'s dialog to name photos; `account.test.ts` shows account delete removes photo files

## 2. AI connector

- [x] 2.1 In `app/worker/relay-mcp/tools.ts`, add the `photos` and `read_photo` tools by the design, let `tool` pass an image answer through, and pass the whole space to `relayServer`; `tools.test.ts` covers paging, the `near` filter, an image answer with its text line, a missing id as a tool error, and that every tool stays read-only with no write SQL
- [x] 2.2 Pass `RELAY_BUCKET` in `mcpHandler` and `env.ts`; bind the bucket in each env of `app/wrangler.relay-mcp.jsonc` and in `self-host/mcp.template.jsonc`; `self-host/bindings.test.mjs` and `setup.test.mjs` pass with the new binding
- [x] 2.3 Update `wiki/stack/relay-ai-connector.md` (the tools and the bucket) and `site/src/content/docs/connections/connect-your-ai.md` (what the AI can read)

## 3. Phone app

- [x] 3.1 Add `photo_manager` and `connectivity_plus` to `mobile/pubspec.yaml`; add `NSPhotoLibraryUsageDescription` to `ios/Runner/Info.plist` and `READ_MEDIA_IMAGES`, `READ_EXTERNAL_STORAGE` (`maxSdkVersion="32"`) and `ACCESS_MEDIA_LOCATION` to `AndroidManifest.xml`; `flutter pub get` and `flutter analyze` pass
- [x] 3.2 Add `photos` and `photosOnMobileData` to `Settings` (each false unless sending, and mobile data false unless photos), with encode and decode tests for old saved settings
- [x] 3.3 Raise the store to schema version 5 with the `photos` queue table, plus `addPhoto`, `waitingPhotos`, `photoDone` and `dropPhotos` (rows and files); store tests cover the upgrade from version 4 and `dropPhotos`
- [x] 3.4 Add `RelayApi.upload` for a multipart body with the same refusal mapping as `post`; tests with a fake client for 200, 400, 403 and offline
- [x] 3.5 Add `lib/sync/photos.dart`: a `PhotoSource` interface and its `photo_manager` version, which finds images taken after `photosAfter`, oldest first, at most 50 a round, and writes each as a JPEG at most 1,600 px with its time and place; a fake source drives the tests
- [x] 3.6 Add the photo step to `backgroundRound` after `flush`: queue new photos, then send the queue only on Wi-Fi or with mobile data allowed; a photo the server turns down (400 or 413) is dropped, a refused one checks the key, and an offline one stops only the photo send; tests show a photo waiting for Wi-Fi never holds back a note, and nothing runs with photos or sending off
- [x] 3.7 Add `setPhotos` and `setPhotosOnMobileData` to `Relay` and the controller: turn-on asks for photo access and stores `photosSince`; turn-off and `stopSending` call `dropPhotos` and clear `photosAfter`; `scheduleSync` runs while photos are on; controller tests cover each
- [x] 3.8 Add the two switches and the turn-off dialog with *Open my page* to `screens/settings.dart`, by the design's UX; widget tests cover the disabled state with sending off, the denied snackbar, and the dialog

## 4. The page

- [x] 4.1 Add `app/src/apps/relay/Photos.tsx` (the count, *No photos yet*, and *Delete all photos* with a confirm dialog) above `<Devices />` in `App.tsx`; tests cover loading, a failed load, the count, and delete

## 5. Website and wiki

- [x] 5.1 Write `site/src/content/docs/app/photos.md` (the switch, Wi-Fi, only new photos, what the phone sends, late arrival on iPhone, deleting on the page), add it to `site/sidebar.mjs` after `app/location`, and add the file to `scripts/product-name.test.mjs`'s list
- [x] 5.2 Update `privacy.md` (photos carry their time and place, stay in the sealed space, go to no webhook) and `app/settings.md` (the two switches)
- [x] 5.3 Add a `HAND_PAGES` entry for `POST photos` in `api-doc.ts`, run `npm run relay:api-doc` in `app/`, and check `api-doc.test.ts` passes
- [x] 5.4 Rename `wiki/relay-spaces.md` *Recordings* to *Recordings and photos* and add the photo file names and the delete route; `memory.mjs areas wiki/relay-spaces.md` finds no link to the old heading left broken

## 6. Bring in the latest version

- [x] 6.1 Resolve each file `git merge origin/main` left in conflict as the union of intent: keep main's spaces design (Durable Objects), data kinds list, share, calendar, phone webhook and brand work, and move the photo work onto them; leave no conflict marker
- [x] 6.2 Add photos to `app/worker/apps/relay/kinds.ts` as a kind with its API route, AI tools and docs page and no webhook tick, so the kinds test passes and photos go to no webhook
- [x] 6.3 When Settings sends straight to one webhook instead of Relay Everything, hide *Photos* and *Send photos on mobile data*, and send no photo; widget and sync tests cover it
- [x] 6.4 Keep shared photos (a note's files, from the share window) and photo sending (the *Photos* switch) apart in `site/src/content/docs/app/photos.md` and the share page: each says what the other does and links to it

## 7. Photos to webhooks

- [x] 7.1 Server: give the `photos` kind in `kinds.ts` a webhook part, marked `sensitive`: log each added photo in `relay_outbox` as the other kinds do, build a `photo.created` message (id, device, taken time, place, width, height, content type, size, and the JPEG in base64, read from the sealed store), drop its `missing.webhook`, and let the webhook form tick *Photos*; update the public schema and the example receiver; tests for a ticked and an unticked webhook
- [x] 7.2 Phone: in webhook mode, show *Photos* and *Send photos on mobile data*, and send each queued photo to the webhook as a signed format v1 `photo.created` with the server's shape; remove the webhook-mode refusal and the drop of waiting photos; controller, sync and widget tests
- [x] 7.3 Docs and specs: say on `privacy.md`, `app/photos.md`, `app/settings.md` and the webhook pages that photos go to a webhook ticked for them, or straight from the phone with no account; update `wiki/relay-webhook-changes.md` if it lists kinds, the design, and the spec deltas (photos webhook requirement, the webhooks capability)

## 8. Checks

- [x] 8.1 Run the app tests, the self-host tests, `flutter test` and `flutter analyze` in `mobile/`, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`
- [x] 8.2 `/save`, then on the preview: deploy the branch's spaces Worker and connector to staging by hand, send a test photo with a phone key on `app-staging.relayeverything.com`, see the count, read it with `read_photo`, delete all photos, and turn the key off
- [ ] 8.3 Check the phone build from the pull request: the Android file installs, *Photos* asks for access, and a new photo shows in the page's count
- [ ] 8.4 On staging, a webhook ticked for *Photos* gets `photo.created` with the photo, and a webhook not ticked gets nothing
