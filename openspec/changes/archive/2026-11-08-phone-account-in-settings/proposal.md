# Sign in, sign out and connections move into Settings, under one Account row

**Status:** ready-to-ship
**Branch:** rethink-connections-settings-ui
**Open questions:** none

## Why

Home has a *Connections* section with *Sending*, *AI apps* and *Webhooks*. It is hard to understand and puts setup next to your notes. You sign in with a *Send my notes* switch, and you sign out with *Disconnect this phone*, which is hidden on the *Sending* page. People look for their account in Settings, as on an iPhone.

## What Changes

- **Home holds only your notes and your phone's data.** The *Connections* section goes. Home keeps *Notes*, *Voice notes* and *Shares*, then *On this phone* with *Location*, *Health*, *Calendar* and *Photos*. The line under *Home* still says *On this phone* or *Synced*.
  ```picture
  Before: pictures/home.jpg
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><span>R</span><span class="grow"/><button class="btn-ghost">⚙</button></div>
    <h3>Home</h3>
    <div class="row gap"><span class="muted">● Synced</span><button class="btn-ghost">↻</button></div>
    <div class="card col gap"><div class="row gap"><span class="grow">Notes</span><span class="muted">12 ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Voice notes</span><span class="muted">3 ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Shares</span><span class="muted">2 ›</span></div></div>
    <div class="row gap"><b class="grow">On this phone</b><span class="muted">⌄</span></div>
    <div class="card col gap"><div class="row gap"><span class="grow">Location</span><span class="muted">Save battery · Sent 14:05 ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Health</span><span class="muted">On ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Calendar</span><span class="muted">Off ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Photos</span><span class="muted">Off ›</span></div></div>
    <div class="row gap"><button class="btn-ghost grow">⌕ Search</button><button class="btn-primary">✎</button></div>
  </div>
  ```
- **An Account row at the top of Settings**, like the Apple Account row on an iPhone. Signed in, it shows the Relay Everything mark, your email and your server. Signed out, it says *Sign in to Relay Everything* and *Your notes stay on this phone until you sign in.* When the phone sends to your own webhook, it says *My own webhook* and the webhook's address.
  ```picture
  Before: pictures/settings.jpg
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Home</button></div>
    <h3>Settings</h3>
    <div class="card row gap"><span class="tag">R</span><div class="col grow"><b>you@example.com</b><span class="muted">app.relayeverything.com</span></div><span class="muted">›</span></div>
    <span class="muted">Appearance</span>
    <div class="card row gap"><span class="tag">System</span><span class="tag-outline">Light</span><span class="tag-outline">Dark</span></div>
    <span class="muted">Notes</span>
    <div class="card row gap"><span class="grow">Pin notes to where I am</span><span class="tag-outline">Off</span></div>
    <span class="muted">Voice notes</span>
    <div class="card col gap"><span>Speech model</span><span class="muted">On this phone, 57 MB.</span></div>
    <span class="muted">Relay Everything 1.0.0 (1)</span>
  </div>
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Home</button></div>
    <h3>Settings</h3>
    <div class="card row gap"><span class="tag">R</span><div class="col grow"><b>Sign in to Relay Everything</b><span class="muted">Your notes stay on this phone until you sign in.</span></div><span class="muted">›</span></div>
    <span class="muted">Appearance</span>
    <div class="card row gap"><span class="tag">System</span><span class="tag-outline">Light</span><span class="tag-outline">Dark</span></div>
  </div>
  ```
- **Signing in starts sending, in one step.** *Sign in to Relay Everything* opens the sign-in. When it works, the phone sends at once, after the question about notes from before. There is no *Send my notes* switch any more. Below *Sign in*, smaller buttons offer *Scan a key*, *Use another server* and *Send to my own webhook instead*. The app stays offline until you do one of these.
  ```mermaid
  flowchart TD
    A["Settings: Sign in"] --> B["Sign in"]
    A --> E["Own webhook"]
    B --> C{"Earlier notes?"}
    E --> C
    C --> D["Sending"]
  ```
- **The Account page holds everything about the connection.** A tap on the Account row opens it. Signed in, it shows your email and server, *AI apps* and *Webhooks* with the names you connected, *Open your Relay Everything page*, and *Sign out* in red. A tap on *AI apps* or *Webhooks* opens that part of your Relay Everything page, where you add or remove one. *Sign out* asks first, then removes this phone's key and stops sending. Your notes from this phone stay. Notes from your other devices leave this phone. With your own webhook, the page shows its address, *Send a test*, and *Stop sending* in red.
  ```picture
  Before: pictures/sending.jpg
  ```
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹ Settings</button></div>
    <h3>Account</h3>
    <div class="card col gap"><b>you@example.com</b><span class="muted">app.relayeverything.com</span></div>
    <span class="muted">Connections</span>
    <div class="card col gap"><div class="row gap"><span class="grow">AI apps</span><span class="muted">Claude · 1 ›</span></div><span class="sep"/><div class="row gap"><span class="grow">Webhooks</span><span class="muted">My database, Zapier · 2 ›</span></div></div>
    <div class="card col gap"><div class="row gap"><span class="grow">Open your Relay Everything page</span><span class="muted">↗</span></div><span class="sep"/><div class="row gap"><span class="grow">Server</span><span class="muted">app.relayeverything.com ✎</span></div></div>
    <div class="card col gap"><span class="danger">Sign out</span><span class="muted">Removes this phone's key and stops sending. Notes from this phone stay here.</span></div>
  </div>
  ```
- **Folders that need sending ask you to sign in.** With sending off, *Location*, *Health*, *Calendar* and *Photos* say they work once you sign in, and their button reads *Sign in*. It opens the same sign-in.
- **The website and the phone app's notes say all of this**, and the iPhone check's Settings tour goes to the Account row in place of Home's *Sending*.

Non-goals: no change to the AI connector itself, its address, or the web page's *AI apps* and *Webhooks* parts. Adding or removing an AI app or a webhook stays on the web page.

## What the build needs

- **Nothing.** The phone already reads the names of your AI apps and webhooks. The server already knows the email of each phone key, so it adds that email to the same answer.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `relay-home-screen`: Home has no *Connections* section; Settings opens on an Account row; the Account page holds sign-in state, AI apps, webhooks, the page link, the server and *Sign out*; folders ask to sign in.
- `relay-sending`: signing in (or choosing one's own webhook) turns sending on in one step, and signing out (or *Stop sending*) turns it off; the place shows on the Account page.

## Impact

- `mobile/lib/screens/home.dart`: remove the *Connections* section and `_connected`; keep `refreshConnections` calls for the Account page.
- `mobile/lib/screens/settings.dart`: new Account row first; new `mobile/lib/screens/account.dart` for the Account page, made from `SendingPage` in `folder.dart` (which goes), with the *AI apps* and *Webhooks* rows moved from `home.dart`.
- `mobile/lib/screens/connect.dart`: titled *Sign in*, with *Sign in to connect* first and *Scan a key*, *Use another server* and *Send to my own webhook instead* below; `choosePlace` stays the one way in.
- `mobile/lib/screens/folder.dart`: the folder pages' *Turn on sending* reads *Sign in*.
- `mobile/lib/relay.dart`, `mobile/lib/controller.dart`: `Connections` gains `email`; *Sign out* is the existing disconnect; *Stop sending* is the existing sending-off for webhook mode.
- Server: `app/worker/apps/relay/connections.ts` answers `email` too (the key's own person, from `caller.email`); `npm run relay:api-doc` in `app/`.
- Tests: `mobile/test/screens_test.dart`, `controller_test.dart`, `offline_test.dart`; `app/worker/apps/relay/connections.test.ts`.
- iPhone check: `mobile/device-check/flows/settings.yaml` (the fixed tour in `tour.sh`); Claude's steps run through `flow.sh` (#68).
- `AGENTS.md` / `CLAUDE.md` *Device keys* line: a phone key also reads its account's email.
- Docs: `mobile/README.md`; website `site/src/content/docs/app/settings.md`, `app/your-notes.md`, `start/connect-a-phone.md`, `connections/index.md`, `api/keys.md`.

## Decision log

- **2026-11-08** — Asked where sign-in and connections go in Settings → chose an Account row at the top of Settings that opens one Account page.
- **2026-11-08** — Asked whether signing in and sending are one step → chose one step: *Sign in* starts sending, *Sign out* stops it, and the own webhook is a smaller *Send to my own webhook instead*.
- **2026-11-08** — Asked what the phone shows for AI apps and webhooks → chose their names, with adding and removing on the web page.
- **2026-11-08** — Assumed: the Account row shows the person's email, because an account row with no name is hard to recognize; the server adds `email` to the names answer a phone key already reads, which holds only the key's own person's email.
- **2026-11-08** — Assumed: a phone that keeps a key with sending off shows *Sign in*, and the sign-in screen offers its kept key in one tap, as today, so no installed phone loses its key.
- **2026-11-08** — Assumed: *Stop sending* in webhook mode keeps the webhook's address and secret on the phone, so choosing it again needs no new secret on the receiver.
- **2026-11-08** — Assumed: the *Server* row stays on the Account page, because a self-hosted server needs it, and *Delete my account* stays on the web page only.
- **2026-11-08** — Assumed: no prototype pictures, because the phone app is Flutter and the plan's prototype runs only the web app; the Before pictures come from the last iPhone check (run 42505968746) and the iPhone check shows the built screens.
- **2026-11-08** — Assumed, from the daily line-up note: the build starts from main with #69 (note delete) and #68 (faster iPhone check), keeps *Delete* in the ⋯ menu and the swipe, and puts the new steps into the check as it is after #68. The note said `tour.sh` became `flow.sh`; on main, `tour.sh` still runs the fixed tour and gates releases, and `flow.sh` runs Claude's own flows, so the Settings steps go in `flows/settings.yaml` for the tour and in the scenarios for Claude.
- **2026-11-08** — Assumed, while building: *Or paste the key* stays on the *Sign in* screen under the three quiet buttons, because a person who opens *Add a device* on the same phone can't scan its own screen.
- **2026-11-08** — Assumed, while building: after *Sign out* or *Stop sending*, the Account page closes back to Settings, which then says *Sign in to Relay Everything*; the *Sign in* screen always opens on *Sign in to connect*, with the webhook one tap away, its address and secret kept.
- **2026-11-08** — Assumed, while building: the narrow-screen check covers the Account page's *Account*, *AI apps*, *Webhooks* and *Sign out*, not *Open your Relay Everything page*, which wraps at 360 px as it did on the old *Sending* page.
- **2026-11-08** — Saved for final acceptance: built, and a second review found two gaps, both fixed: the fixed tour's `timeline.yaml` still looked for Home's *AI apps* row, and no controller test proved *Stop sending* keeps the webhook. A test for the checker's empty email closes the last uncovered branch. `flutter analyze` is clean, all 480 phone tests pass, and the app suite passed but for a 5-second timeout in `Welcome.test.tsx`, a file this change does not touch, at a load of about 15; it passes alone. The iPhone device check (4.2) runs on this saved commit.
- **2026-11-08** — Check: the iPhone device check on 6443018 (run 42526509209) gave *works*: the fixed tour passed all four flows, and Claude saw Home with no *Connections*, Settings opening on *Sign in to Relay Everything*, the *Sign in* screen with its three quiet buttons, Health asking to sign in, and *Delete* still in a note's ⋯ menu. The signed-in Account page and the webhook state were not shown on the iPhone, because the check has no account; widget tests cover them.
- **2026-11-08** — Archived for the ship. Main moved on with #73 (a voice note opens its page when it saves) and #74 (WongStack 51.4); merged with no conflict, and `flutter analyze` and all 487 phone tests pass on the merge.
