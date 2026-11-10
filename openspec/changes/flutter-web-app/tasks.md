# Tasks

## 1. Shared code builds for the web

- [x] 1.1 Move `newClientId` to `mobile/lib/data/client_id.dart` and import it from the controller and `note_editor.dart`; `flutter analyze` and `flutter test` pass.
- [x] 1.2 Add `Relay.platform` and an `EntryFile` image and audio source that reads a file on the phone or the server route on the web; update `timeline.dart` and `note_blocks.dart`; screen tests pass for both platforms with the fakes.
- [x] 1.3 Add `mobile/web/` and `lib/main_web.dart`, and a test that fails when any library `main_web.dart` reaches imports `dart:ffi` or a phone-only plugin; `flutter build web -t lib/main_web.dart --no-web-resources-cdn` succeeds.

## 2. The page writes notes as the Web device

- [x] 2.1 Add `asDeviceOrPage` and the space's *Web* device; use it for `POST`, `PATCH`, `DELETE notes` and `POST attachments`. Route tests: a session adds, edits and deletes a note named by *Web*; a cross-origin change is refused; a session reaches only its own space; webhooks get the messages.
- [x] 2.2 Run `npm run relay:api-doc` in `app/` and update `wiki/relay-spaces.md` (how a space is opened) with the page's writes; the api-doc test passes.

## 3. WebRelay and the notes screens in a browser

- [x] 3.1 Write `WebRelay` over the page's routes with the session cookie: load, page and search notes, add, edit, delete with *Undo*, add files, open a file, play a recording, sign out; no browser storage. Unit tests with a fake HTTP client.
- [x] 3.2 Hide the phone-only parts on the web (health, places, calendar, photos switches, speech model, own webhook, voice, QR scan); screen tests check each is absent on the web and present on the phone.
- [x] 3.3 Write the Flutter sign-in screen (email code, Apple, Google, contact line, `next` return); widget tests with a fake client.

## 4. The wide layouts

- [x] 4.1 Build the responsive shell: three panes at 1,000 px and wider, two panes from 700, the phone layout below; the open note and its unsaved words survive a resize. Widget tests at 1440, 900 and 390 px.
- [x] 4.2 Add the left bar (folders with counts, *Other connections*, *Settings* at the bottom) and the one top bar (new note, Aa, checklist, paperclip, Share, ⋯, search at the right, no bottom bars); widget tests that search filters the list and nothing shows at the bottom.
- [x] 4.3 Add keyboard shortcuts (new note, search, bold, italic, delete) and file drop onto a note; widget tests for each shortcut and the drop.

## 5. The rest of the old page in Flutter

- [x] 5.1 The get-the-app page for Location, Health, Calendar and Photos (links to the app for iPhone and Android; Photos also shows the count and *Delete all*); widget tests that it shows no health, place or calendar data.
- [x] 5.2 Chats: the list and one chat with its saves, paging and delete; widget tests.
- [x] 5.3 The Settings dialog with its pages down the left, closing back to the open note: Account (email, sign out, delete account), Devices (list, *Add a device* with its QR code shown once, *Turn off*, API key), Webhooks (add, edit kinds, secret, test, resend, retry, remove), AI apps (list, disconnect), Email notes (address, new address), Appearance; widget tests for each against fixture answers taken from the React tests.
- [x] 5.4 Show the new Settings pages in the phone app where its key may read them, and only the names it reads today where it may not; screen tests.

## 6. Serve the build and remove the React page

- [x] 6.1 Build the web app into `app/public/apps/relay/` from `build:app` (which `cf-build.sh` runs), `deploy.yml` and `scripts/publish-relay-server.mjs`, with the engine's fallback fonts from the server; serve it before the single-page fallback; remove `app/src/apps/relay/*` except `app.json`, and `src/relay-only.tsx`; keep the `relay-only` Vite mode for the server's Worker and a redirect `index.html`; teach the mini-app list a static app. `npm test` and `npm run build` in `app/` pass, and `/apps/relay/` answers the Flutter page on a local run.
- [x] 6.2 Attach `relay-web-<commit>.zip` with its SHA-256 to each `main` publish and release, and make `app/self-host/setup.mjs` download, check and unpack it, stopping before deploy when it is missing; `setup.test.mjs` covers both; update `app/self-host/SETUP.md`.
- [x] 6.3 Update `scripts/product-name.test.mjs`'s list with the new user-facing Dart files; the test passes.

## 7. Docs and website

- [x] 7.1 Update the website's pages about the Relay Everything page (`site/src/content/docs/app/`) with the wide layout, writing notes in the browser and the new pictures; update `wiki/relay-website.md`, `wiki/stack/mini-apps.md` (a static mini app) and `mobile/README.md` (the web build); `node scripts/publish-relay-site.mjs --ref HEAD --staging` shows them.

## 8. Checks

- [x] 8.1 Run `flutter analyze`, `flutter test`, the web build, `npm test` in `app/`, and `node scripts/public-check.mjs`; all pass.
- [ ] 8.2 `/save`, then on staging sign in at 1440 and 390 px wide: write a note, add a file, edit it, delete and undo, see it on a phone's sync, open each connection, Chats and each Settings page; take the preview pictures.
