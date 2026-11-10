## Context

See proposal.md, Why. Today `/apps/relay/` is a React mini app (`app/src/apps/relay/`, and `app/src/relay-only.tsx` on the shared server and a self-host). It reads the person's space with the session cookie and changes no note: `POST`, `PATCH`, `DELETE notes` and `POST attachments` take only a device key (`asDevice`).

The phone app's screens read and act through one interface, `Relay` in `mobile/lib/relay.dart`; `RelayController` implements it over the drift store, the key vault and the phone's sensors. A probe on 2026-11-09 (`.scratch/webprobe`, `flutter build web`) showed:

- `lib/main.dart` fails for the web on `whisper_cpp_flutter_plus` (`dart:ffi`), reached through `controller.dart`.
- `app.dart` with every screen builds for the web once `note_editor.dart` stops importing `controller.dart` for `newClientId`. `main.dart.js` is 1.5 MB.
- The plan's pictures come from a throwaway prototype in `.scratch/flutter-web-app-prototype/` (`lib/main_proto.dart`: a `LayoutBuilder` shell around `TimelineScreen` and `NoteEditor`, the test `FakeRelay` with sample notes, and pages for the Settings dialog, a get-the-app page and Sign in). It shows the shared screens run in a browser at 1280 and 390 px. The build reads it first, then builds the real shell.
- `timeline.dart` and `note_blocks.dart` use `dart:io` `File` for pictures and recordings: they compile, but fail at run time in a browser.

## Goals / Non-Goals

**Goals:**
- One Flutter codebase for the phone and the browser; the screens stay shared.
- The browser app has every part of the old page but the day summary, and writes notes.
- No Flutter needed on a self-hoster's computer.

**Non-Goals:**
- No offline notes, service worker or install as a desktop app.
- No voice recording or speech model in the browser.
- No macOS or Windows desktop build.
- No change to what a phone key reaches.

## Decisions

### A web entry and a `WebRelay`, not the phone controller on the web

`lib/main_web.dart` starts `RelayApp` with a `WebRelay`, a `Relay` that reads and writes the person's space through the page's own routes (`GET notes`, `POST`/`PATCH`/`DELETE notes`, `POST attachments`, `GET attachment`, `GET audio`), with the session cookie. It keeps notes in memory only. Its phone-only members (health, places, calendar, photos, speech model, voice, webhook) return off states and are never shown: a `Relay.platform` getter (`phone` or `web`) tells screens to hide them.

*Alternative:* run `RelayController` on the web with drift's wasm SQLite. Rejected: it keeps a second copy of the notes in the browser, which the spec forbids on a shared computer, and drags in the sensors' plugins behind stubs.

### Split the phone-only imports

- `newClientId` moves to `lib/data/client_id.dart`, so no screen imports `controller.dart`.
- Pictures and recordings in `timeline.dart` and `note_blocks.dart` go through an `EntryFile` image provider: `FileImage` on the phone, `NetworkImage` of `api/attachment?id=` on the web. A recording plays through `Relay.play`, which `WebRelay` does with `just_audio` from `api/audio?id=`.
- `connect.dart`'s QR scanner, `url_launcher`, `share_plus`, `file_picker` and `package_info_plus` all have web support; the scanner is not shown on the web (no key to scan into a browser).
- A CI step builds `main_web.dart` for the web, so a new phone-only import fails the check, not the deploy.

### The responsive shell

`RelayApp` wraps Home in a `LayoutBuilder` shell with three widths: `>= 1000` three panes (folders, list, note), `700–999` two panes with folders in a menu, `< 700` today's `Navigator` pages. In the wide layouts the note's app bar becomes one top bar (new note, Aa, checklist, paperclip, Share, ⋯, and a search field bound to the list's filter at the right); the editor's bottom bars hide there, and the phone keeps them. The shell holds the open note's id in one place, so a resize keeps it; the editor already saves as you type. The note pane reuses `NoteEditor`'s body without its page chrome. The list reuses `timeline.dart`'s grouped cards. On the phone the shell picks the phone layout always, so the phone app does not change; an iPad gets the wide layouts as a side effect.

*Alternative:* a separate desktop widget tree. Rejected: two copies of each screen go stale.

### The page writes as the space's *Web* device

`asDevice` gets a sibling, `asDeviceOrPage`, for the four note routes. A session caller (or Access email on a self-host) gets the space's *Web* device, made on first use like the inbox's *Email* device (`token_client_id` `page:web`, no key, `reaches` `phone`). The gate's Origin check for a session already covers these routes. Webhooks and the phones' sync name the change's device as for any other. The `relay-device-keys` promise stays: no key gains reach.

### Serve the build as static files at `/apps/relay/`

`flutter build web -t lib/main_web.dart --base-href /apps/relay/ --no-web-resources-cdn` writes `mobile/build/web/`, and the app build copies it to `app/public/apps/relay/` (git-ignored). `--no-web-resources-cdn` keeps CanvasKit and the app's own fonts on the server. The engine's fallback fonts for emoji and other scripts come from `fonts.gstatic.com` by default, so `mobile/web/flutter_bootstrap.js` sets `fontFallbackBaseUrl` to the page's `fallback-fonts/`, and `scripts/build-relay-web.mjs` reads the engine's own font list from the built `main.dart.js`, fetches each file once at build time, and puts it there, in the page and in the self-host zip. So the page loads nothing from Google. The Workers' assets answer `/apps/relay/*` before the single-page fallback. The React page goes. The `relay-only` Vite mode stays for the shared server and a self-host: it builds only their Worker, and an `index.html` that sends `/` to `/apps/relay/`. In the company app, `app/src/apps/relay/` keeps only `app.json` for the home card, and the mini-app list learns a folder with a static build (`app.json` with `"static": true`). The AI connector's sign-in return and the sign-in routes stay server routes, so their links keep working; the Flutter app reads the `next` query as the React page did.

### Build in CI, download on a self-host

- `deploy.yml`'s build job installs Flutter from `mobile/pubspec.yaml` before `cf-build.sh --build-only`, whose `build:app` runs the web build, on every pushed branch, so a phone-only import fails there. `mobile-ci.yml` runs `flutter test` when `mobile/` changes, and builds the release zip on `main` and a release. `test.yml` builds nothing with Flutter.
- `scripts/publish-relay-server.mjs` runs the web build in its exported copy (this computer has Flutter in `/opt/flutter`).
- A `v<x.y.z>` release, and each publish to `main`, attaches `relay-web-<commit>.zip`. `app/self-host/setup.mjs` downloads the zip for its commit, checks its SHA-256 from the release, and unpacks it into `public/apps/relay/`; a missing zip stops the install before any deploy.

### Sign-in screen in Flutter

The sign-in screen posts to the same `sign-in/` routes as the React page (email code), and opens Apple and Google by navigating the window to their start routes, which return to `/apps/relay/` with the cookie set. `Contact` shows `RELAY_CONTACT_EMAIL` as before.

## UX

### Use-case brief
Matthew, and any signed-in person, at a computer. The job: read, find and write notes with a keyboard, and manage devices, webhooks and AI apps. Done: the same notes and the same look as the phone, in a window that uses its width. Context: a desktop or laptop browser, often beside other work, sometimes a narrow window. The common case is reading and writing notes; Settings is rare. Mirror Apple Notes on macOS, as the phone mirrors Apple Notes on iOS 26.

### Flow
Open the page → signed in → *Notes* with the newest note open → type in it, or press *New note* (⌘⌥N / Ctrl+Alt+N) → words save as you type. Find: ⌘F or the search field at the top right → the list filters → click a note. Connections: the left bar's *Health* (or Location, Calendar, Photos) → a get-the-app page; *Claude Code chats* → the chats in the middle and right panes. Settings: the left bar's bottom *Settings* → a dialog over the notes → close it, and the note is as it was. Edge: signed out → sign-in → back to the notes.

### Hierarchy
- Notes: the one primary action is *New note*, at the left of the top bar; *Search* sits at its right end; Share and ⋯ sit quiet beside search. Nothing at the bottom.
- Left bar: the notes folders first, *Other connections* below, *Settings* alone at the bottom.
- Get-the-app page: the store buttons lead.
- Settings dialog: each page's one action (*Add a device*, *Add a webhook*) is primary; *Turn off* and *Delete account* stay ghost or danger.

### Review
`openspec/changes/flutter-web-app/review.html`. The What Changes items show prototype pictures of the notes (computer and phone), a get-the-app page, the Settings dialog and sign-in.

### Components
The phone app's existing widgets: `timeline.dart` cards, `NoteEditor` and its Quill toolbars (`note_bars.dart`), `folder.dart`, `settings.dart`, `account.dart`, `brand.dart` colors, Inter and `CupertinoIcons`. New: the responsive shell, the top bar, the left bar (folders, *Other connections*, *Settings*), the get-the-app page, a Settings dialog, a QR code widget for *Add a device* (`qr_flutter`), and the Chats, Devices, Webhooks, AI apps, Email notes, Photos and Delete account pages, ported from the React parts with the same server answers. On the phone, Home keeps *On this phone*; the web names it *Other connections*.

## Risks / Trade-offs

- [The first load is larger than the React page: about 1.5 MB of app code plus CanvasKit] → serve CanvasKit from the server with long cache headers; show the brand mark while it loads.
- [A new phone-only import breaks the web build] → the CI web build fails the change and names the file.
- [Flutter web text selection and right-click feel less native than a web page] → turn on `SelectionArea` on read-only text, and keep the browser's own context menu in text fields (`BrowserContextMenu`).
- [A self-host update on a commit with no release zip] → the setup stops before deploying, and the guide says to update to a release.
- [Search engines index the page less] → the page is behind sign-in, so nothing is lost; the website stays the public face.
- [This is large] → the tasks build in order: shared code, web notes, server writes, other screens, builds; each group lands its own tests, so the change can stop after notes if needed.

## Migration Plan

1. Ship server and app together: the server's new page writes need no client change, and the old React page goes in the same publish.
2. Publish deploys the company app; `publish-relay-server.mjs` deploys the shared server with the new static build.
3. Roll back with `publish-relay-server.mjs --ref <earlier commit>`; no data shape changes, and a *Web* device row is harmless to the old page.
