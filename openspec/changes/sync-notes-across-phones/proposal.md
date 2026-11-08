# Your notes on every phone you sign in on

**Status:** planned; the build starts after *Edit notes like Apple Notes* is published
**Branch:** funny-warthog
**Open questions:** none

## Why

Today each phone only sends notes up. A note you write on one phone never shows on your other phone, and a new phone starts empty. Your notes are already together on your Relay Everything page, so a signed-in phone should get them from there too, the same as Apple Notes on an iPhone and an iPad.

## What Changes

- **Every signed-in phone shows all your notes.** With sending on and Relay Everything picked, the phone gets your notes from your space: notes from your other phones, email, Claude Code, your AI apps and the web API. A new phone gets all your old notes the first time. A note from somewhere else shows where it came from. New notes come in when you open the app, when you pull down the list, and in the hourly background round.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><h3>Notes</h3><span class="grow"/><button class="btn-ghost">⋯</button></div>
    <span class="muted">Today</span>
    <div class="card col"><b>Call the dentist</b><span class="muted">9:41</span></div>
    <div class="card col"><b>Flight to Lisbon, seat 14A</b><span class="muted">8:02 · Email</span></div>
    <div class="card col"><b>Ideas for the ring app</b><span class="muted">7:15 · Pixel 9</span></div>
    <div class="row gap"><span class="tag-outline">Search</span><span class="grow"/><button class="btn-primary">✎</button></div>
  </div>
  ```
- **You can edit any note on any phone.** Change a note on one phone, and your other phones, your page and Claude get the new words. If two phones change the same note before they sync, the newer change wins, and the older one is replaced on both phones.
  ```mermaid
  sequenceDiagram
    participant A as iPhone
    participant S as Your space
    participant B as Pixel
    A->>S: New words for a note
    S-->>B: The changed note, at the next sync
    B->>S: A newer change of the same note
    S-->>A: The newer words replace the older ones
  ```
- **A note's files open when you tap them.** Each note shows its photos and files by name and size. A file downloads only when you open it, so the phone uses no space or data for files you never look at. Voice recordings stay on the phone that made them, so other phones get the words only.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">‹</button><span class="grow"/><button class="btn-ghost">⋯</button></div>
    <h3>Flight to Lisbon, seat 14A</h3>
    <span class="muted">From Email · 8:02</span>
    <div class="card row gap"><span>📄</span><span class="grow">boarding-pass.pdf</span><span class="muted">240 KB · tap to open</span></div>
  </div>
  ```
- **Your webhooks get it all, through the server.** Each new note and each change, from any phone, goes to your space, and the server sends it on to your webhooks as `note.created` or `note.updated`. So you get sync and your own database together. In Settings, *My own webhook* says that it turns sync off, and links to adding the webhook on your page instead.
  ```mermaid
  flowchart LR
    A[iPhone] --> S[Your space]
    B[Pixel] --> S
    S --> A
    S --> B
    S --> W[Your webhooks]
  ```
- **A signed-in phone can read your notes, and nothing more.** Today a phone's key can only send. Now it can also read your notes and their files, but still not your health, places, calendar or photos. *Turn off* on your page stops it at once. Signing out on a phone removes the notes that came from somewhere else, and keeps the ones you wrote on it. The privacy page and the keys page say this.
  | A phone's key | Before | After |
  |---|---|---|
  | Send notes, health, places, calendar, photos | Yes | Yes |
  | Read notes and open their files | No | Yes |
  | Edit notes | Only its own | Any note |
  | Read health, places, calendar, photos | No | No |
- **Offline stays the default.** With sending off, the app makes no network call and gets no notes, as today. With *My own webhook* picked, the phone sends there and never syncs through Relay Everything. Turning sending off keeps the notes already on the phone.
  | Setting | Sends | Gets your other notes |
  |---|---|---|
  | Sending off | Nothing | No |
  | Relay Everything | To your space | Yes |
  | My own webhook | To your webhook | No |

Non-goals: deleting a note everywhere, sync on the web page as a phone app, syncing health, places or photos, and syncing through your own webhook server.

## What the build needs

- **The editing change, published first**: Ready. *Edit notes like Apple Notes* is built and in its last checks in its own chat. It adds note changes on the phone and the server, and this build starts once it is published.
- **Keys, accounts and packages**: Ready. Nothing new is needed. There are no real phone pictures, because this computer has no Flutter to run the app, so the sketches stand in.

## Capabilities

### New Capabilities
- `relay-note-sync`: a signed-in phone gets every note in its person's space and their changes, edits any note with the newer change winning, opens files on tap, keeps sync off with sending off or its own webhook, and removes synced notes on sign-out; every change from any phone goes to the server's webhooks.

### Modified Capabilities
- `relay-device-keys`: a phone key reads its person's notes and their files, and changes any note in that space; it still reads no health, place, calendar event, chat or photo.

## Impact

- Space migration `0011_note_sync.sql`: a `relay_note_changes` log with a growing number per change, filled by triggers on `relay_notes` and `relay_attachments`, and filled once for the notes already there.
- Server, in `app/worker/apps/relay/`: a new `GET notes` route (changes since a number) for a session or a phone key; `PATCH notes` (from the editing change) takes a server `id` too, for any note in the space, and refuses a change older than the note's last one; `caller.ts` lets a phone key reach `GET notes`, `GET attachment` and `GET audio`; `npm run relay:api-doc`.
- Phone, in `mobile/lib/`: `data/store.dart` keeps each note's server id, device name and edit time, and a sync number; a new `data/note_sync.dart` pulls changes; `controller.dart`, `sync/background.dart` and the notes list pull on open, on pull-down and hourly; `data/connection.dart` removes synced notes on sign-out; the note page opens a synced file on tap; Settings explains that *My own webhook* turns sync off.
- Rules and docs: the *Device keys* rule in `AGENTS.md`; `wiki/relay-spaces.md`; the website's privacy, keys and notes pages.

## Decision log

- **2026-11-08** — Asked how this plan goes with the unpublished note editing change → chose: plan here, build after editing is published, on top of it.
- **2026-11-08** — Asked what a signed-in phone can do with a note from somewhere else → chose: read and edit any note; the newer change wins.
- **2026-11-08** — Asked how far a phone's reading goes → chose: a signed-in phone's key reads notes, not health, places or photos; *Turn off* stops it; the privacy page says so.
- **2026-11-08** — Asked whether files come down to other phones → chose: on tap, not all at once and not words only.
- **2026-11-08** — Asked how sync and webhooks work together → chose: through the server; it sends every note and change from any phone on to the person's webhooks.
- **2026-11-08** — Assumed: *the newer change* is the one with the later edit time from its phone, not the one that reached the server last, because a phone offline for a day would otherwise overwrite newer words when it comes back.
- **2026-11-08** — Assumed: any phone key reads, whether it came from *Sign in to connect* or a QR code on the page, because both are made only by the signed-in person, and both stop with *Turn off*.
- **2026-11-08** — Assumed: signing out removes notes that came from elsewhere and keeps notes written on the phone, because a phone handed to someone else should not keep the rest of your space.
- **2026-11-08** — Assumed: a note emptied and deleted on one phone stays on the others and on the page, because the page can't delete a note yet, and deleting everywhere is a non-goal.
- **2026-11-08** — Assumed: old ring recordings open on tap like files, and a phone's voice recordings stay on their phone, because the server never got those recordings.
- **2026-11-08** — Assumed: sync pulls on app open, return to the app, pull-down and the hourly round, with no live push, because the phone has no push channel today and a minute's delay is fine for notes.
