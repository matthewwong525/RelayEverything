---
title: Notes
description: Read the notes you write on your phone, open your Relay page for ring notes, and write a new note.
---

The Relay app opens on your notes, newest first. It shows the notes that you type or say into this phone. It keeps them on the phone.

Ring notes and recordings are on your Relay page, not in the app. Your phone's key can only send to your Relay server. It can not read your notes from the server.

## Read your notes

Each note shows:

- **Voice** or **Typed**: how you made the note.
- **Play** on a voice note: its recording, from this phone. A voice note shows **Writing the words…** until the phone writes them. [Voice notes](../voice-notes/)
- The note's words.
- When you made it and where you were. With sending off, a pinned note shows **Pinned**: the phone does not look up the place's name.
- With sending on, **Sent** or **Waiting to send**. **Sent** means your server has the note. **Waiting to send** means the note goes on the next sync.

## Open your Relay page

With sending on, a card at the top of the list says *Ring notes and recordings are on your Relay page.* Tap **Open your Relay page**. The phone's browser opens `<your-relay-server>/apps/relay/`. Sign in with your email. Your ring notes, their recordings, and the notes from all your devices are there.

With sending off, the card does not show.

## Write a note

1. Tap **New note**.
2. Type the note. The keyboard opens at once.
3. Tap **Save**.

The note shows at once, with or without a signal. With **Pin notes to where I am** on, it keeps where you are; the pin follows when the phone has a fix. With sending on, the note also goes to your server. If the phone sends a note two times, for example after it lost the server's answer, your server keeps it one time.

## Talk a note

Hold **Hold to talk**, talk, and let go. The phone writes the words itself. [Voice notes](../voice-notes/)

## Where a ring note's place comes from

The Pebble ring sends no place. With sending and **Location history** on, a ring note takes the history point nearest in time, up to 10 minutes before or after you spoke. You see the place on your Relay page. [Location](../location/) tells more.

## The sync mark

The mark at the top says where your notes are. With sending on, tap it to sync now. You can also pull the list down.

| Mark | What it means |
|---|---|
| **On this phone** | Sending is off. Your notes stay on this phone, and the app sends nothing. [Connect a phone](../../start/connect-a-phone/) to turn it on. |
| **Synced** | Your server has all the notes from this phone. |
| **Syncing** | The phone sends notes now. |
| **2 waiting** | Notes made with no signal. They show **Waiting to send** and go on the next sync. |
| **Offline** | The phone can not reach your server. You lose nothing. |
| **Key refused** | The server refused this phone's key. [Connect the phone](../../start/connect-a-phone/) with a new key. |
