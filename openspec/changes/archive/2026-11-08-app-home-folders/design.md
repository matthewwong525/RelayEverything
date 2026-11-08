# Design: Home of folders

## Context

See proposal.md, Why. Today `RelayApp` opens `TimelineScreen` (`mobile/lib/screens/timeline.dart`), which owns the notes list, search, the ⋯ menu, the dock, the listening card overlay and the Shortcuts voice stream. `SettingsScreen` holds three groups; its *Sending* group holds the sending switch, Health, Calendar, Location history and its modes, the place, the webhook and the server. A phone key reaches only POST routes and `GET key` (`app/worker/apps/relay/caller.ts`, `REACH` and `reaches()`). The server already lists AI apps (`ai-apps.ts`, through the connector's `Grants.list`) and webhooks (`relay_webhooks` in the person's space), for a signed-in person only.

## Goals / Non-Goals

**Goals:** a new first screen made from today's parts; the data switches moved, not changed; one narrow read for the phone key.

**Non-Goals:** a new table or migration; managing AI apps or webhooks on the phone; any change to what or when the phone sends; the album *Photos* folder.

## Decisions

### Home is a new screen; the timeline becomes a folder

`HomeScreen` (`screens/home.dart`) becomes `RelayApp.home`. It takes over from `TimelineScreen` the parts that must live once per app: the `notices` snack bars, the listening overlay (`_showListening`), the `voiceRequests` subscription, the ⋯ menu and its `_openPage`. `TimelineScreen` keeps the day groups, rows, its own search and the dock, and gains a `NotesFolder` value (`all`, `voice`, `shares`) and a title. *Alternative:* a tab bar. Rejected: the person asked for Apple Notes' Folders screen, and tabs would hide Connections behind one more tap.

`NotesFolder.shares` matches a note with an attachment, or whose words hold an `http://` or `https://` link. The count on Home runs the same filter over `relay.entries`, so the count and the list always agree. One `entryIn(folder, entry)` function serves both and has its own test.

### Data folders reuse the Settings rows

The Health, Calendar, Location history and Sending rows move from `settings.dart` into `screens/folder.dart` as four small pages, each a `ListenableBuilder` on `relay`, with the same `_apply`, `_choosePlace`, `_stopSending`, `_editServer`, `_disconnect` and `_test` behavior. The shared parts (`_Group`, `sentLine`, `problemLine`, the place line) move with them. The Home row text comes from one function per folder (`locationLine`, `healthLine`, `calendarLine`, `sendingLine`), tested alone. *Turn on sending* calls the same `_choosePlace` that the sending switch calls.

### The phone key reads names through one new route

`GET /apps/relay/api/connections` answers `{ aiApps: [{ name }], webhooks: [{ name }] }` from the caller's own space and the connector's grant list. Only a phone key passes: `reaches()` lets `GET` through for `KEY_CHECK` and, for `reach === "phone"`, for this one path. A signed-in browser may call it too, as the page's routes allow. No address, secret, kinds or send state leave. When the connector is not set up, `aiApps` is an empty list, not an error, so Home still shows webhooks.

*Alternative:* add the names to the `GET key` answer. Rejected: `GET key` is the connect check that every key type uses, and a chat key must not learn the names.

The phone calls it after each successful sync, and when Home opens, only while `settings.sending && settings.place == SendPlace.server`. It keeps the last answer in the `state` table under `connections`, so Home shows names with no signal. Turning sending off or disconnecting clears it.

### Opening a part of the page

A tap on *AI apps* or *Webhooks* opens `<server>/apps/relay/#ai-apps` or `#webhooks`. The page gets an `id` on those two cards (`AiCard.tsx`, `Webhooks.tsx`), so the browser scrolls to them. This adds no new route.

### The back button names its page

`BackToNotes` becomes `BackTo(label)`; every page opened from Home shows *‹ Home*. The note page, opened from a folder, shows the folder's name.

## UX

### Use-case brief

Who: a person who uses Relay Everything on their own phone, alone. The job: see what Relay Everything keeps and sends for them, and get to any part in one tap. Most of the time the job is still *write or say a note now*, so the *New note* button stays on Home. Done: the person sees their notes, each data stream's state, and what they connected, on one screen. Context: a phone, one hand, often a quick open. Common case: open, tap *New note* or *Notes*. Edge cases: turn a data stream on or off, check why something waits, sign in. Frequency: Home opens several times a day; a folder page a few times a week; Sending once a month.

### Flow

Open → Home → *New note* (one tap, as before) or a folder → its page. Sending off → a data folder → *Turn on sending* → the same *Where should the phone send?* screen as today. Not signed in → *AI apps* → the same screen. Signed in → *AI apps* → the browser at that part of the page.

### Hierarchy

Home: the one primary action is *New note*, filled accent with the glow. Folder icons are accent text, rows are ink, statuses and counts are muted. *Sign in to see* is accent text with no fill, so it reads as a link, not a second primary action. A folder page: the switch is the main control; with sending off, *Turn on sending* is the one filled button.

### Review

[review.html](review.html). What Changes items 1 (Home, in the prototype), 3 (a data folder) and 4 (the Connections flow) show each screen.

### Components

Existing: `SliverAppBar.large`, the `_Group` cards from Settings, `SwitchListTile`, `RadioListTile`, `ListTile`, the dock, `NewNoteButton`, `_MoreMenu`, the sync line, `RelayMark`. New: `_FolderRow` (icon, title, status line, count, chevron) and `_FoldHeader` (a section name with a turning chevron), both in `home.dart`, because no screen has them yet.

## Risks / Trade-offs

- [The phone key now reads something] → only names, only the caller's own space, only for `phone` reach; a test proves a chat key and an API key are refused, and that no address or secret is in the answer.
- [The device check and its flows start on the notes list] → the flows tap *Notes* first; `timeline.yaml` and `new-note.yaml` change in the same task as the screen.
- [The email-notes work, open in another chat, edits `api.ts`, `device.ts` and the Relay Everything page] → this change adds a file and one line each to `api.ts`'s route list and `caller.ts`; whoever ships second merges.
- [A person on their own webhook sees *Sign in to see*, and signing in moves the phone to the server] → the screen that opens is the same choice of place as today, which says what each choice does.

## Migration Plan

No data moves. The server route ships with the app; an older app never calls it, and a newer app on an older server gets a 403 and shows *AI apps* and *Webhooks* with no names, still opening the page. Rollback: revert the change.
