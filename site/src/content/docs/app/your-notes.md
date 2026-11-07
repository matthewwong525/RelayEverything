---
title: Notes
description: Read the notes you write on your phone, add photos and files to a note, open your Relay Everything page for ring notes, and write a new note.
---

The Relay Everything app opens on your notes, newest first. It shows the notes that you type or say into this phone. It keeps them on the phone.

Ring notes and recordings are on your Relay Everything page, not in the app. Your phone's key can only send to your Relay Everything server. It can not read your notes from the server.

## Read your notes

Each note shows:

- **Voice** or **Typed**: how you made the note.
- **Play** on a voice note: its recording, from this phone. A voice note shows **Writing the words…** until the phone writes them. [Voice notes](../voice-notes/)
- The note's words.
- The note's files: pictures small, and other files as a row with name and size. [Add photos and files](#add-photos-and-files)
- When you made it and where you were. With sending off, a pinned note shows **Pinned**: the phone does not look up the place's name.
- With sending on, **Sent** or **Waiting to send**. **Sent** means your server has the note. **Waiting to send** means the note goes on the next sync.

## Open your Relay Everything page

With sending on, a card at the top of the list says *Ring notes and recordings are on your Relay Everything page.* Tap **Open your Relay Everything page**. The phone's browser opens `<your-relay-server>/apps/relay/`. Sign in with your email. Your ring notes, their recordings, and the notes from all your devices are there.

With sending off, the card does not show.

## Write a note

1. Tap **New note**.
2. Type the note. The keyboard opens at once.
3. Tap **Save**.

The note shows at once, with or without a signal. With **Pin notes to where I am** on, it keeps where you are; the pin follows when the phone has a fix. With sending on, the note also goes to your server. If the phone sends a note two times, for example after it lost the server's answer, your server keeps it one time.

## Add photos and files

A note can hold photos, screenshots, PDFs and other files of any kind.

1. Tap **New note**.
2. Type the note, or leave it empty: a note can be only files.
3. Tap **Add photo or file**, and pick photos or files from the phone. Each one shows under the words, with its name and size. Tap its cross to take it off.
4. Tap **Save**.

A note holds up to 10 files, each up to 25 MB. The app refuses a file over 25 MB, or an eleventh file, with a message, and keeps the rest. You can't change a note's files after you save it.

In your notes, a picture shows small, and another file shows as a row with its name and size. Tap a file to open it.

Where the files go:

- **On this phone**, always. iPhone backups keep them, because a file you added may be nowhere else. Android cloud backup leaves them out, because it holds at most 25 MB for an app.
- **In your space**, only with sending on. Each file goes after its note, sealed with your space's own key. When you turn sending on, [**Send them**](../../start/connect-a-phone/) sends the files of earlier notes too. [Privacy](../../privacy/)
- **On your Relay Everything page**, a picture shows in its note, and another file is a link that downloads it. A file that has not arrived yet shows *Waiting for the file*.
- **To your webhooks**, only each file's name, type and size, never the file: [Your own database](../../connections/your-database/#a-notes-files).

[Shortcuts](../shortcuts/) can also add a note with files, with no tap in the app.

To keep a web page, a photo or a file from another app, use its share button: [Share from any app](../share/). A shared note has no place.

## Talk a note

Hold **Hold to talk**, talk, and let go. The phone writes the words itself. [Voice notes](../voice-notes/)

## Where a ring note's place comes from

The Pebble ring sends no place. With sending and **Location history** on, a ring note takes the history point nearest in time, up to 10 minutes before or after you spoke. You see the place on your Relay Everything page. [Location](../location/) tells more.

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
