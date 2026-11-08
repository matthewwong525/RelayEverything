# Open the phone app on a Home screen of folders, like Apple Notes

**Status:** building
**Branch:** rethink-relay-app-ui
**Open questions:** none

## Why

The app opens on the notes list, and everything else hides in one long Settings list: location, health, the calendar, where the phone sends. A person can not see at a glance what Relay Everything keeps for them or what it is connected to. This change opens the app on a *Home* screen of folders, like Apple Notes' *Folders* screen. Notes are one folder, each kind of phone data has its own folder, and what you connected sits under its own header.

## What Changes

- **Home is the first screen.** A large *Home* title, the sync state under it, and the ⋯ menu at the top right. Three cards follow, each a list of folders with a count or a status and a chevron. The first card is your notes. *On this phone* holds Location, Health and Calendar. *Connections* holds where the phone sends, your AI apps and your webhooks. *Search* and the round *New note* button stay at the bottom, so you still write or talk in one tap. Search on Home finds notes in every folder. Each header folds away, like in Apple Notes. Tap through every screen below, in light and dark.
  ```live
  folder: prototypes/app
  height: 940
  ```
  ```picture
  Before: pictures/before-timeline.webp
  ```
  The *Before* is today's first screen, from the last iPhone check. The *After* is the prototype above, because the phone app does not run in the plan's preview.
- **Your notes, split by kind.** *Notes* shows every note. *Voice notes* shows only voice notes. *Shares* shows notes with a photo, a file or a link. Each one opens today's list, grouped by day, with *‹ Home* at the top left. There is no new note type: these are three views of the same notes.
- **A folder for each kind of phone data.** *Location*, *Health* and *Calendar* each open a page with their switch and their status: *Off*, or when it was last sent and how many wait. Location also holds *Save battery* or *Every 100 m*, and Calendar holds the list of calendars. The phone keeps no new copy of your places or readings. With sending off, a folder says it works only with sending on, and its one button turns sending on, in the same steps as today.
  ```screen
  <div class="card col gap phone">
    <span class="muted">‹ Home</span>
    <h3>Location</h3>
    <div class="row gap"><span class="grow">Location history</span><span class="tag">On</span></div>
    <span class="muted">Sent 14:05 · none waiting</span>
    <div class="sep"></div>
    <div class="row gap"><span class="grow">Save battery</span><span class="tag-outline">✓</span></div>
    <div class="row gap"><span class="grow">Every 100 m</span></div>
  </div>
  ```
- **Connections, which the phone knows once you sign in.** *Sending* says where this phone sends: *Off*, your Relay Everything server, or your own webhook. Its page holds today's sending switches, the webhook test, the server and *Disconnect this phone*. When the phone is signed in to your Relay Everything server and sending is on, *AI apps* and *Webhooks* show what you connected, such as *Claude* or *2 webhooks*. A tap opens that part of your Relay Everything page to change it. Not signed in, or sending off, each of those rows says *Sign in to see*, and a tap starts the same sign-in as today. The phone's key can then read the names of your AI apps and webhooks, but never your notes, health, places or chats.
  ```mermaid
  flowchart TD
    A["Tap AI apps"] --> B{"Signed in and sending on?"}
    B -->|"no"| C["Sign in to connect"]
    C --> D["Phone asks the server"]
    B -->|"yes"| D
    D --> E["Claude · connected"]
    E -->|"tap"| F["Your page, AI apps part"]
  ```
- **Settings gets small.** It keeps *Notes* (*Pin notes to where I am*) and *Voice notes* (the speech model). Everything about sending moves to *Sending* under *Connections*, and each data switch moves into its own folder.
- **The website says the same.** The app pages on relayeverything.com describe Home, the folders and *Connections*, and the API page lists the new connections route.

Non-goals: syncing the photo album (planned next, as its own *Photos* folder under *On this phone*); a *Ring* row, an *Email notes* row or *Add a service* before each one works; folders you make yourself; changing AI apps or webhooks from the phone; any change to what a switch sends.

## What the build needs

- **Nothing.** The phone app, the server and the website build with what is here. The iPhone check uses the device check that runs on each save.

## Capabilities

### New Capabilities

- `relay-home-screen`: the phone app's first screen: the notes folders, the *On this phone* folders with their status and controls, the *Connections* rows, search across notes, and the small Settings.

### Modified Capabilities

- `relay-notes-screen`: the notes list opens from a Home folder and shows that folder's notes; the ⋯ menu moves to Home.
- `relay-device-keys`: a phone key may also read the names of its person's AI apps and webhooks, and no other data.
- `relay-app-background`: the send status for Health and Location history shows in their folders, not in Settings.

## Impact

- `mobile/lib/screens/home.dart` (new): Home, its cards, its headers and its search; `screens/folder.dart` (new): the Location, Health, Calendar and Sending pages, moved out of `settings.dart`.
- `mobile/lib/screens/timeline.dart`: takes a filter (all, voice, shares) and a title, gets *‹ Home*, and loses the ⋯ menu; the listening card and the Shortcuts voice requests move to Home so they work on any page.
- `mobile/lib/screens/settings.dart`: only *Notes* and *Voice notes*; `back_to_notes.dart` becomes a back button that names its page.
- `mobile/lib/data/`: a call for `GET connections` and the last answer kept in `state`; `mobile/lib/relay.dart` and `controller.dart` expose it.
- `app/worker/apps/relay/connections.ts` (new) and `caller.ts`: `GET /apps/relay/api/connections` for phone keys only; `api-doc` regenerated.
- `mobile/test/`, `app/worker/apps/relay/*.test.ts`, `mobile/device-check/flows/`: tests and flows for the new start screen.
- `AGENTS.md` (the *Device keys* rule), `wiki/relay-spaces.md`, `mobile/README.md`, and the website's app pages.
- No new table, no migration. The new route reads the existing `relay_webhooks` names and the AI connector's grant list.

## Decision log

- **2026-11-08** — Asked, in chat, how the app should open → chose a Home screen of folders like Apple Notes, not the notes list, with location, health and the rest out of Settings, and connected services under their own header.
- **2026-11-08** — Asked what a Location or Health folder shows → chose *Status and controls*: the switch, the mode, the last send and what waits, with no new copy of places or readings on the phone.
- **2026-11-08** — Asked what goes under the second header → chose *All connections* in one list.
- **2026-11-08** — Asked whether the notes card splits notes by kind → chose *Split by kind*: *Notes*, *Voice notes* and *Shares*, as views of the same notes, with no new note type.
- **2026-11-08** — Asked, in chat, whether album photos come in as notes → each album photo is not a note; album sync becomes its own *Photos* folder under *On this phone*, in a later change.
- **2026-11-08** — Asked where the ring goes before it works → chose *Hide until it works*.
- **2026-11-08** — Asked what *Connections* rows show, since the phone's key can not read → chose, in their own words, that the app asks you to sign in for what needs the connection, and once signed in it knows.
- **2026-11-08** — Assumed: once signed in, the phone key reads only the names of the person's AI apps and webhooks, through one new route, because that is all the rows show, and a lost phone's key must still not read notes, health, places or chats.
- **2026-11-08** — Assumed: the phone asks for that status only while sending is on to a Relay Everything server, because the app makes no network call while sending is off.
- **2026-11-08** — Assumed: a tap on *AI apps* or *Webhooks* opens that part of the Relay Everything page, because changing them on the phone is a bigger build and the page already does it.
- **2026-11-08** — Assumed: *Email notes* and *Add a service* stay off Home until each one works, the same as the ring, because a row that does nothing confuses.
- **2026-11-08** — Assumed: the large title says *Home* and a page opened from it shows *‹ Home*, because *Relay Everything* is long for a back button and the R mark already names the app at the top left.
- **2026-11-08** — Assumed: *Shares* holds the notes with a photo, a file or a link, because the phone keeps no mark of which notes came from the share button, and the album will get its own *Photos* folder.
- **2026-11-08** — Assumed: search on Home finds notes in every folder, and search in a folder finds notes in that folder, as in Apple Notes.
- **2026-11-08** — Assumed: the ⋯ menu (*Settings*, *Sync now*, *Open your Relay Everything page*) lives on Home only, and a pull on any notes list still syncs, because one menu is easier to find than two.
- **2026-11-08** — Assumed: each header folds and the phone remembers it, as in Apple Notes.
- **2026-11-08** — Assumed: a folder row shows what the phone already knows, such as *Every 100 m · Sent 14:05*, and no count per day, because the phone does not count points per day.
- **2026-11-08** — Assumed: the plan's *After* is a drawn HTML prototype, because the phone app does not run in the plan's preview; the iPhone check after the build shows the real screens.
- **2026-11-08** — Assumed: the phone reads the names when Home opens and after a full sync, at most each 10 minutes, because a read after every sync sends a request each few minutes for names that seldom change.
- **2026-11-08** — Assumed: signed in, with no answer from the server yet, *AI apps* and *Webhooks* say *See them on your page*, and with an empty answer *None yet*, because a blank row reads as broken.
- **2026-11-08** — Assumed: *Sign in to see* opens the same choice of place as the sending switch, because that is today's sign-in.
- **2026-11-08** — Assumed: a cleared search on Home shows the folders again, and an empty folder says what goes in it and that notes stay on the phone until sending is on.
- **2026-11-08** — Assumed: a data folder with sending off says *Location history works with sending on. Nothing leaves this phone until you turn it on.*, with one *Turn on sending* button.
- **2026-11-08** — Assumed: the tests for the names read sit in `controller_test.dart`, beside the other sending tests, not in `sync_test.dart`.
- **2026-11-08** — Assumed: the Relay Everything page waits for the day summary, the notes and the chat list before it scrolls to *AI apps* or *Webhooks*, because a list that loads above the card after the scroll pushes it out of view.
