---
title: Notes
description: Home and its folders, read and search the notes you write on your phone, write a new note with photos and files, and open your Relay Everything page for ring notes.
---

The Relay Everything app opens on **Home**, a screen of folders. Your notes are the first folders. The app shows the notes that you type or say into this phone, and keeps them on the phone.

Ring notes and recordings are on your Relay Everything page, not in the app. Your phone's key can only send to your Relay Everything server. It can not read your notes from the server.

## Home

Home has a large **Home** title, the [sync state](#the-sync-state) under it, and the [⋯ menu](#the--menu) at the top right. Then three cards of folders. Each row shows a name, its status or its count, and a chevron. Tap a row to open it.

| Card | Folder | What it holds |
|---|---|---|
| Your notes | **Notes** | Every note on this phone. |
| | **Voice notes** | Only the notes you said. [Voice notes](../voice-notes/) |
| | **Shares** | The notes with a photo, a file or a link. |
| **On this phone** | **Location** | Location history: *Off*, or its mode and when the points last went, such as *Save battery · Sent 14:05*. [Location](../location/) |
| | **Health** | *Off*, or when the readings last went and how many wait. [Health](../health/) |
| | **Calendar** | *Off*, or how many calendars and when the events last went. [Calendar](../calendar/) |
| | **Photos** | *Off*, or *On* and if photos also go on mobile data. [Photos](../photos/) |
| **Connections** | **Sending** | Where the phone sends: *Off*, your Relay Everything server, or your own webhook. [Sending](../settings/#sending) |
| | **AI apps** | The AI apps you connected on your Relay Everything page, such as *Claude*. [Connections on Home](#connections-on-home) |
| | **Webhooks** | The webhooks you added on your Relay Everything page. [Connections on Home](#connections-on-home) |

Tap **On this phone** or **Connections** to fold that card away. Tap it again to open it. The phone remembers which cards you folded.

**Search** and **New note** stay at the bottom of Home, so you still write or talk with one tap.

## Connections on Home

While the phone sends to your Relay Everything server, **AI apps** and **Webhooks** show the names of what you connected on your Relay Everything page, as the server last told the phone, and how many. Tap one to open that part of your Relay Everything page in the phone's browser. You change them there, not in the app. With no signal, the rows show the last names the phone got.

With sending off, or while the phone sends to your own webhook, each row says *Sign in to see*. Tap it to choose where the phone sends: [Connect a phone](../../start/connect-a-phone/).

To show these names, the phone's key reads only the names of your AI apps and webhooks. It reads no address, secret, note, health data, place or chat. The phone asks for the names only while it sends to your Relay Everything server.

## Read your notes

Tap **Notes**, **Voice notes** or **Shares** on Home. The folder shows its notes, newest first, under its name. Tap **Home** at the top left to go back. The notes are in groups by day: **Today**, **Yesterday**, **Previous 7 days**, **Previous 30 days**, then one group for each month. Each group is one card, with one row for each note:

- The note's first line, in bold. A voice note shows **Writing the words…** until the phone writes them. [Voice notes](../voice-notes/)
- The time, then the rest of the words. Today and yesterday show the time, this week the day, and older notes the date.
- **Voice** or **Typed**: how you made the note. Then the length of a voice note, and where you were. With sending off, a pinned note shows **Pinned**: the phone does not look up the place's name.
- With sending on, **Sent** or **Waiting to send**. **Sent** means your server has the note. **Waiting to send** means the note goes on the next sync.
- The first picture, small, at the right. [Add photos and files](#add-photos-and-files)

Before your first note, **Notes** says **No notes yet**: *Tap New note to write one, or hold it to talk.* An empty **Voice notes** says *Hold New note to talk.*, and an empty **Shares** says *A note with a photo, a file or a link shows here.* With sending off, each also says *Notes stay on this phone until you turn on Sending on Home.*

## Open a note

Tap a note's row to read all of it on its own page:

- The date, the time and the place.
- All of its words.
- Each picture, full width. Tap a picture to open it.
- Each other file, as a row with its name and size. Tap it to open it.
- **Play** on a voice note: its recording, from this phone. [Play a note back](../voice-notes/#play-a-note-back)
- **Voice** or **Typed**, and **Sent** or **Waiting to send**.

You read a note on this page. You can not change a note after you save it. Tap the folder's name at the top left, such as **Voice notes**, to go back.

## Search your notes

1. Tap **Search**, at the bottom of Home or of a folder.
2. Type a word. The list shows only the notes with that word in their words, their place or their file names. Upper and lower case are the same. On Home, search finds notes in every folder. In a folder, it finds only that folder's notes.
3. Tap **Cancel** to see Home or all the folder's notes again.

Search reads only the notes on this phone, so it works with no signal and sends nothing. With no match, the list says *No notes with "<your words>"*.

## The ⋯ menu

The round **⋯** button at the top right of Home holds:

| Item | Shows | What it does |
|---|---|---|
| **Settings** | Always | Opens [Settings](../settings/). |
| **Sync now** | With sending on | Sends what waits, now. |
| **Open your Relay Everything page** | With sending to your Relay Everything server | Opens `<your-relay-server>/apps/relay/` in the phone's browser. Sign in with your email. Your ring notes, their recordings, and the notes from all your devices are there. |

## Write a note

1. Tap **New note**, the round green button at the bottom right. A short tap opens the **New note** page. A hold records a voice note: [Talk a note](#talk-a-note).
2. Type the note. The keyboard opens at once. The first line shows in bold, as the note's title.
3. Tap **Save**, at the top right.

The note shows at once, with or without a signal. With **Pin notes to where I am** on, it keeps where you are; the pin follows when the phone has a fix. With sending on, the note also goes to your server. If the phone sends a note two times, for example after it lost the server's answer, your server keeps it one time.

## Add photos and files

A note can hold photos, screenshots, PDFs and other files of any kind.

1. Tap **New note**.
2. Type the note, or leave it empty: a note can be only files.
3. Tap **Add photo or file**, the paperclip at the bottom, and pick photos or files from the phone. Each one shows under the words, with its name and size. Tap its cross to take it off.
4. Tap **Save**.

A note holds up to 10 files, each up to 25 MB. The app refuses a file over 25 MB, or an eleventh file, with a message, and keeps the rest. You can't change a note's files after you save it.

In your notes, the first picture shows small at the right of the note's row. On the note's own page, each picture shows full width, and another file shows as a row with its name and size. Tap a file to open it.

Where the files go:

- **On this phone**, always. iPhone backups keep them, because a file you added may be nowhere else. Android cloud backup leaves them out, because it holds at most 25 MB for an app.
- **In your space**, only with sending on. Each file goes after its note, sealed with your space's own key. When you turn sending on, [**Send them**](../../start/connect-a-phone/) sends the files of earlier notes too. [Privacy](../../privacy/)
- **On your Relay Everything page**, a picture shows in its note, and another file is a link that downloads it. A file that has not arrived yet shows *Waiting for the file*.
- **To your webhooks**, each file after its note, with its bytes: [Your own database](../../connections/your-database/#notefile). A receiver that refuses a file as too large skips it, and the file stays in your space.

[Shortcuts](../shortcuts/) can also add a note with files, with no tap in the app.

To keep a web page, a photo or a file from another app, use its share button: [Share from any app](../share/). A shared note has no place.

## Talk a note

Hold **New note** for half a second. The phone buzzes, and the button turns into an amber mic. Let go, and talk: the phone keeps listening. Tap anywhere on the screen to save. The phone writes the words itself. [Voice notes](../voice-notes/)

## Where a ring note's place comes from

A ring note keeps the place it already has, which you see on your Relay Everything page. Relay Everything gives no ring note a place later: a ring note with no place keeps none. [Location](../location/) tells how a typed note gets its place.

## The sync state

The line under the **Home** title gives the sync state, such as *Synced*. Under a folder's name, it also gives how many notes the folder holds, such as *5 notes · Synced*. With sending on, a small dot is beside the state, and you can tap the state to sync now. You can also pull Home or a folder down, or tap **Sync now** in the ⋯ menu.

| State | Dot | What it means |
|---|---|---|
| **On this phone** | No dot | Sending is off. Your notes stay on this phone, and the app sends nothing. [Connect a phone](../../start/connect-a-phone/) to turn it on. |
| **Synced** | Green, still | Your server has all the notes from this phone. |
| **Syncing** | Amber, pulses | The phone sends notes now. If the phone is set to reduce motion, the dot stays still. |
| **2 waiting** | Hollow | Notes made with no signal. They show **Waiting to send** and go on the next sync. |
| **Offline** | Hollow | The phone can not reach your server. You lose nothing. |
| **Key refused** | Red | The server refused this phone's key. [Connect the phone](../../start/connect-a-phone/) with a new key. |
