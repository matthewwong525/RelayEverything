# The Relay Everything web page becomes the phone app, sized for a computer

**Status:** in-progress
**Branch:** flutter-app-with-notes
**Open questions:** none

## Why

The Relay Everything web page and the phone app look and work differently. The page is one long column of cards, and it only reads notes: you can't write, change or delete one there. The phone app has the good note screens. With one app on both, a person gets the same notes, the same look and the same editor on their phone and their computer, and each new screen is built once.

## What Changes

- **The web page is the Flutter app.** Opening Relay Everything in a browser starts the same app as the phone, with its brand look, icons and editor. It replaces the current page on the shared server, on a self-hosted server and in the company app. The address stays the same, so links and bookmarks keep working.
  ```mermaid
  flowchart TD
    B["Browser opens /apps/relay/"] --> F["Flutter app"]
    F --> S{"Signed in?"}
    S -- "no" --> I["Sign in: email code, Apple, Google"]
    S -- "yes" --> H["Notes"]
    I --> H
  ```

- **A wide window looks like Apple Notes on a Mac.** The left bar holds the phone's own Home: *Notes*, *Voice notes* and *Shares*, then *Other connections*, with *Settings* at its bottom. The middle shows the open folder's notes by day. The open note fills the right, where you type straight into it. One bar runs along the top: *New note*, the text tools and the paperclip, then Share, ⋯ and *Search* at the top right. Nothing sits at the bottom. A narrower window drops the left bar to a menu, and a window as narrow as a phone shows the phone layout. The pictures come from a prototype: the phone app's own screens, built for the browser, with sample notes.
  ```picture
  Notes, computer: pictures/notes-computer.png
  Notes, phone: pictures/notes-phone.png
  ```

- **You write, change and delete notes in the browser.** *New note* opens an empty note on the right, and the words save as you type, with the same styles, lists, checklists and links as on the phone. Drag a file onto a note, or use the paperclip, to add a picture or file. Delete has *Undo*, as on the phone. A change shows on your phone at its next sync, and goes to your webhooks and AI apps as a phone's change does. Keyboard keys work: a new note, search, and bold or italic. Voice notes play, but you record them on the phone: the browser has no speech model.
  ```mermaid
  sequenceDiagram
    participant P as Browser
    participant S as Your space
    participant M as Your phone
    P->>S: New note, as you type
    S-->>M: Next sync shows it
    M->>S: An edit on the phone
    S-->>P: Shows when you come back to the tab
  ```

- **Other connections: what your phone and computer send.** Under the notes folders, the left bar lists *Location*, *Health*, *Calendar*, *Photos* and *Claude Code chats*. For now, Location, Health, Calendar and Photos open a page that says the phone sends them, with links to get the app. The Photos page also keeps the photo count and *Delete all*, as today. A later change lets you look through each kind of data there. *Claude Code chats* opens your saved chats, as the page does today. The phone switches for each, the speech model and *Send to my own webhook* stay only in the phone app.
  ```picture
  Health, computer: pictures/health-computer.png
  ```

- **Settings opens in a window over your notes.** *Settings* at the bottom of the left bar opens a dialog with its pages down the left: *Account* (email, sign out, delete account), *Devices* (*Add a device* with its QR code), *Webhooks*, *AI apps*, *Email notes* and *Appearance*. Each works as it does today. The phone app gets the same pages in its Settings where its key may read them.
  ```picture
  Settings, computer: pictures/settings-computer.png
  ```

- **Today's summary leaves the web page.** The steps, sleep, heart rate, calendar and places at the top of today's page go. They come back inside Health, Location and Calendar when those pages show your data.

- **Signing in looks like the app.** The browser shows the app's own sign-in: an email code, *Sign in with Apple* or *Sign in with Google*, as today. Signing out goes back to it. A self-hosted server behind Cloudflare Access opens straight to the notes, as today.
  ```picture
  Sign in, computer: pictures/signin-computer.png
  ```

- **The website's pages about the web page change to match**, with new pictures of the wide layout.

## What the build needs

- **Flutter on this computer**: Ready, Flutter 3.47.9 is in `/opt/flutter`.
- **Flutter on GitHub's build machines**: Ready, the phone builds already install it from `mobile/pubspec.yaml`.
- **Nothing else.** No new key or account.

## Capabilities

### New Capabilities

- `relay-web-app`: the Flutter app in a browser: where it is served, the wide and narrow layouts, sign-in, notes written from the page, and the screens that replace the old page.

### Modified Capabilities

- `relay-self-host`: an install serves the Flutter web build without the person installing Flutter.

## Impact

- `mobile/`: a web entry (`lib/main_web.dart`) and a `WebRelay` that implements `Relay` against the server with the page's session; platform-only imports split behind conditional imports; a responsive shell (three panes, two panes, phone) around the existing screens; the left bar with *Other connections* and its get-the-app page, Chats, and a Settings dialog with Account, Devices, Webhooks, AI apps, Email notes and Appearance; `web/` folder. New tests for each.
- `app/worker/apps/relay/`: `POST`, `PATCH`, `DELETE notes` and `POST attachments` also take a signed-in session, written by the space's own *Web* device, as the inbox writes as *Email*.
- `app/`: the React page (`src/apps/relay/`, `src/relay-only.tsx`) goes; the build copies the Flutter web build to `/apps/relay/`. The company app's mini-app list keeps its entry.
- Builds: `deploy.yml`, `mobile-ci.yml` and `scripts/publish-relay-server.mjs` build the web app with Flutter; a release attaches the built web page, which `app/self-host/setup.mjs` downloads.
- `site/`: the docs pages about the web page, and `npm run relay:api-doc` for the route change.
- `wiki/relay-spaces.md`, `wiki/relay-website.md`, `mobile/README.md`.

## Decision log

**2026-11-09** — Asked what happens to the parts the phone app doesn't have (today, webhooks, devices, AI apps, chats, photos, email notes, account delete) → chose all in Flutter: the whole web page is one Flutter app, and the React page goes.

**2026-11-09** — Asked how the app should look in a wide window → chose Notes for Mac style: list on the left, the open note on the right, folding to the phone layout in a narrow window.

**2026-11-09** — Assumed: the browser keeps no notes of its own and reads and writes the person's space directly, because a web page is always signed in and has no offline promise to keep, and a second copy in the browser would need its own sync.

**2026-11-09** — Assumed: no voice recording in the browser, because the speech model is a phone download and the server writes no words; voice notes made elsewhere still play.

**2026-11-09** — Assumed: notes written in the browser are signed by a *Web* device in the space, with no key, as email notes are signed by *Email*, because notes, webhooks and the phone's sync all name a device.

**2026-11-09** — Assumed: a self-hosted install downloads the web build from the matching GitHub release, because asking each self-hoster to install Flutter would make the install much harder.

**2026-11-09** — Asked to remove the ring from all public text → this plan names no ring: no *Ring* folder, label or text in the new screens. Old ring notes show as plain notes.

**2026-11-09** — Asked, in notes on the plan, for one top bar like Apple Notes with Search at the top right and nothing at the bottom, a left bar that matches the phone's Home with *Other connections* in place of *On this phone*, no *Your day* section, Settings at the bottom of the left bar, and Settings in a dialog → done, and the prototype pictures retaken.

**2026-11-09** — Asked, in notes on the plan, that Location, Health, Calendar and Photos in the left bar open a page that sends people to get the app for now, and show their data in a later change → done; today's summary at the top of the old page goes until then.

**2026-11-09** — Assumed: *Claude Code chats* sits under *Other connections* and opens the saved chats, because the old page shows them, the phone can't, and they are one more thing a connection sends.

**2026-11-09** — Assumed: the Photos page keeps the photo count and *Delete all* from the old Settings, because a person must still be able to delete their photos from the browser.

**2026-11-09** — Assumed: *Other connections* is the web's name only; the phone keeps *On this phone*, because there the data does come from that phone.

**2026-11-09** — Assumed: the Settings pages new to the browser also show in the phone app, because they share code and the phone already shows the names of AI apps and webhooks.

**2026-11-09** — Assumed: a new note is Ctrl+Alt+N (⌘⌥N), because browsers keep Ctrl+N for a new window; delete is Ctrl+Shift+Backspace (⌘⇧Backspace), because Ctrl+Backspace deletes a word. In the open note, Ctrl+F goes to the page's search, not the editor's own find box.

**2026-11-09** — Assumed: the phone app keeps its phone layout at any width; only the browser uses the wide layouts. In the browser, *Appearance* lasts until a reload, because the browser keeps nothing.

**2026-11-09** — Assumed: the *Web* device is stored with reach `inbox`, so Devices hides it and the space needs no schema change; a page change by Access email now needs the page's own Origin.

**2026-11-09** — Assumed: a file dropped on the page with no note open starts a new note; the browser sends each change at once, after the editor's pause.

**2026-11-09** — Assumed: the get-the-app page links the App Store and the Android download on GitHub, not Google Play, because the app is not on Google Play.

**2026-11-09** — Assumed: the web build runs in `build:app`, not in `cf-build.sh`, because `cf-build.sh` is a WongStack file that stays the same in every repo.

- **2026-11-09** — Check: `app/worker/apps/relay/device.test.ts` now expects 403 for a cross-site change by Access email, not 200, because page writes need the page's own Origin; this makes the check stricter.

- **2026-11-09** — Check: `app/src/apps/relay/AiCard.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/App.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/Inbox.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/Notes.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/Photos.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/SignIn.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/apps/relay/Webhooks.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `app/src/relay-only.test.tsx` is deleted with the React page it tested, because that page is gone; the Flutter tests in `mobile/test/web_*_test.dart` and `mobile/test/connection_page_test.dart` take its place.

- **2026-11-09** — Check: `.github/workflows/deploy.yml` adds a pinned Flutter setup step before the app's build, because the build now makes the web page; it removes no step.

- **2026-11-09** — Check: `.github/workflows/mobile-ci.yml` adds the `web` and `web-beta` jobs, and the release job waits for `web`, because each publish needs the web build and its zip; no job is removed or skipped.

- **2026-11-09** — Check: `app/knip.jsonc` drops `src/relay-only.tsx` from its entry files, because that file is deleted with the React page; knip checks the rest as before.

**2026-11-10** — Assumed: CanvasKit's fallback fonts for emoji and other scripts come from the server, not `fonts.gstatic.com`: the page's own `flutter_bootstrap.js` sets `fontFallbackBaseUrl`, and the build fetches the engine's own font list, read from the built page, into it, about 24 MB, so the self-host zip carries them too, because the design promises the page loads nothing from Google.

**2026-11-10** — Assumed: the page's own `flutter_bootstrap.js` starts no service worker, because Flutter's default one keeps the page's files in the browser, and the browser keeps nothing.

**2026-11-10** — Assumed: a change to a note that gets no answer, or a server fault, stays as typed and goes again at the next save, when the note closes, at each sync and as the page closes; any other refusal takes the note back to its words before, because sending it again can not help.

**2026-11-10** — Assumed: the web build check runs in `deploy.yml` on every pushed branch, not in `test.yml`, and the docs now say so, because that build already fails on a phone-only import, and a second Flutter build would only add time.

**2026-11-10** — Assumed: a new note that gets no answer, or a server fault, stays with its files and goes again as new, by the same `clientId`, at the same times as a change; any other refusal, such as a 400 or a 409, takes it away. If the server says it already had the note, the words go after as an edit. As the page closes, the open note's words not yet saved go too, because the save waits 1.5 s after typing stops.

- **2026-11-09** — Check: `app/package.json` runs `build-relay-web.mjs` in `build:app`, adds `../scripts/build-relay-web.test.mjs` to `test`, and removes `uqr`, which only the React page used; no check is taken out.

**2026-11-10** — Built: every task but the live check on the preview. Two review rounds fixed ten problems: phone edits to an open note, coming back to the tab, failed saves, uploads and new notes, the phone's Settings links, deletes at sign-out, a new device in the list, and words typed just before the tab closes.
