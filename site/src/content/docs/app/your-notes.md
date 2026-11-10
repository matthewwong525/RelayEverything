---
title: Notes
description: Home and its folders, read, search and change the notes you write on your phone, as in Apple Notes, with text styles, checklists, photos and files, and open them on a computer.
---

The Relay Everything app opens on **Home**, a screen of folders. Your notes are the first folders. The app shows the notes that you type or say into this phone, and keeps them on the phone. Once you sign in to Relay Everything, it also shows the notes from your other phones, email, Claude Code, Codex and your AI apps: [Your notes on every phone](#your-notes-on-every-phone).

## Home

Home has a large **Home** title, the [sync state](#the-sync-state) under it, and the round [gear button](#the-gear-and-your-relay-everything-page) at the top right. Then three cards of folders. Each row shows a name, its status or its count, and a chevron. Tap a row to open it.

| Card | Folder | What it holds |
|---|---|---|
| Your notes | **Notes** | Every note on this phone. |
| | **Voice notes** | Only the notes you said. [Voice notes](../voice-notes/) |
| | **Shares** | The notes with a photo, a file or a link. |
| **On this phone** | **Location** | Location history: *Off*, or its mode and when the points last went, such as *Save battery · Sent 14:05*. [Location](../location/) |
| | **Health** | *Off*, or when the readings last went and how many wait. [Health](../health/) |
| | **Calendar** | *Off*, or how many calendars and when the events last went. [Calendar](../calendar/) |
| | **Photos** | *Off*, or *On* and if photos also go on mobile data. [Photos](../photos/) |
| **Other connections** | **AI chat transcripts** | How to save your chats from Claude Code and Codex, and, when you are signed in, a link to read them on the web. [Save AI chat transcripts](../../connections/claude-code/) |

Tap **On this phone** or **Other connections** to fold that card away. Tap it again to open it. The phone remembers which cards you folded.

**Search** and **New note** stay at the bottom of Home, so you still write or talk with one tap.

Home holds no setup. Your account, sign-in, AI apps and webhooks are in [Settings](../settings/#account), on its first row.

## Read your notes

Tap **Notes**, **Voice notes** or **Shares** on Home. The folder shows its notes, newest first, under its name. Tap **Home** at the top left to go back. The notes are in groups by day: **Today**, **Yesterday**, **Previous 7 days**, **Previous 30 days**, then one group for each month. Each group is one card, with one row for each note:

- The note's first line, in bold, without its style marks. A voice note shows **Writing the words…** until the phone writes them. [Voice notes](../voice-notes/)
- The time, then the rest of the words. Today and yesterday show the time, this week the day, and older notes the date. A note from somewhere else also shows where it came from, such as *8:02 · Email*.
- **Voice** or **Typed**: how you made the note. Then the length of a voice note, and where you were. With sending off, a pinned note shows **Pinned**: the phone does not look up the place's name.
- With sending on, **Sent** or **Waiting to send**. **Sent** means your server has the note. **Waiting to send** means the note goes on the next sync.
- The first picture, small, at the right. [Add photos and files](#add-photos-and-files)

Before your first note, **Notes** says **No notes yet**: *Tap New note to write one, or hold it to talk.* An empty **Voice notes** says *Hold New note to talk.*, and an empty **Shares** says *A note with a photo, a file or a link shows here.* With sending off, each also says *Notes stay on this phone until you sign in, in Settings.*

## Open and change a note

Tap a note's row to open it on its own page:

- The date, the time and the place.
- All of its words, in their styles.
- Each picture, full width. Tap a picture to open it.
- Each other file, as a row with its name and size. Tap it to open it.
- **Play** on a voice note: its recording, from this phone. [Play a note back](../voice-notes/#play-a-note-back)
- **Voice** or **Typed**, and **Sent** or **Waiting to send · Send now**. Tap **Waiting to send · Send now** to send what waits now. It says **Sending…** while it goes.

A web address in the words, such as `https://example.com` or `www.example.com`, shows in green and underlined. Tap it to open it in the phone's browser. This works for an address that you typed or pasted as plain text too. While you type, a tap on a link puts the cursor there, as in Apple Notes. The note's words do not change: the link shows only on the phone.

The page works as in Apple Notes: you change the note in place. Tap the words where you want to type. The cursor goes there and the keyboard comes up. There is no **Save** button: the phone keeps each change as you type, and when you leave the page. You can change a voice note's words too. Its recording stays as it was.

At the top of the page:

- **‹** and the folder's name, such as **Voice notes**, at the left, go back to the folder.
- **Share** and **⋯**, in a round button at the right. **⋯** opens a menu under it with **Copy**, which copies the words without their style marks, and **Play** on a voice note.
- **✓**, while you type, closes the keyboard. The change stays.

While you type, a round bar floats above the keyboard: **Aa** for [text styles](#text-styles-and-checklists), the checklist button, and the paperclip to [add photos and files](#add-photos-and-files). With the keyboard closed, a bar at the bottom holds the checklist button, the paperclip, and the round compose button, which starts a new note.

If you leave a note with no words and no files, the app deletes it, as Apple Notes does. A note that your server has, or that is on its way to it, is deleted everywhere, with **Undo**, as when you [delete a note](#delete-a-note). A voice note keeps its recording.

## Text styles and checklists

Tap **Aa** while you type. A panel comes up in place of the keyboard:

| Style | What it does |
|---|---|
| **Title**, **Heading**, **Subheading**, **Body** | Sets the size of the line the cursor is on. The first line of a new note starts as a **Title**. |
| **Monostyled** | Shows the line in a font with letters of one width, as for code. |
| **B**, **I**, **U**, **S** | Makes the words you selected bold, italic, underlined or struck through. |
| Bulleted, dashed and numbered lists | Starts a list. Tap return on an empty item to end the list. |
| Block quote | Shows the line as a quote, with a bar at its left. |
| Indent in and out | Moves a line, or a list item, in or out by one step. |

Tap the checklist button to make the line a checklist item, with a round circle at its left. One tap on the circle ticks the item, in green. Another tap clears it. The circle works with the keyboard closed too, so you can tick items as you shop.

The page shows each style as it looks. Inside, the note keeps its styles as plain Markdown marks, so your Relay Everything page, your AI and your webhooks read them as normal text:

| On the phone | In the words |
|---|---|
| Title, Heading, Subheading | `# `, `## `, `### ` at the start of the line |
| Monostyled | A code block: a line of three backticks before it and after it |
| Bold, italic, struck through | `**words**`, `_words_` (`*part*` of a word), `~~words~~` |
| Underline | `<u>words</u>` |
| Bulleted, dashed and numbered lists | `* `, `- ` and `1. ` at the start of the line |
| Checklist | `- [ ] ` open, `- [x] ` ticked |
| Block quote | `> ` at the start of the line |
| Indent | Two spaces for each step in |

Your notes list shows the first line and the start of the rest without these marks. A note that you wrote before styles came opens with the same words, and its first line shows as a title. It does not change until you change it.

## Delete a note

Delete a note in one of two ways:

- In a folder's list, swipe the note's row to the left.
- On the note's page, tap **⋯**, then **Delete**, the last item, in red. The page closes.

The note leaves the list at once, and the bar at the bottom says **Note deleted**, with **Undo**. Tap **Undo** in the next 5 seconds to get the note back as it was. After that, the phone deletes the note, its files and its recording. With a screen reader, each note's row has a **Delete** action.

With sending on, the delete then goes everywhere: your server deletes the note, its files and its recording, and your page, your AI and your other phones no longer show it. Each of your webhooks gets one [`note.deleted`](../../connections/your-database/#notedeleted) message. You can delete any note, also one from email or another phone. After the 5 seconds you can't undo it.

A delete made with no signal goes on the next sync. With sending off, a note that your server has keeps its delete on the phone, and the delete goes when you turn sending on again, so the note does not come back. A note that never went is deleted from the phone only.

## Change a sent note

With sending on, a change to a note that your server already has goes to your server when you stop typing. Your Relay Everything page and your AI then read the new words in place of the old ones, and each of your webhooks gets one [`note.updated`](../../connections/your-database/#noteupdated) message. With **My own webhook**, the phone sends `note.updated` there itself.

A change made with no signal, or while the note waits to send, goes on the next sync. Only the latest words go. You can change any note on any signed-in phone, also a note from email or another phone: [Your notes on every phone](#your-notes-on-every-phone).

With sending off, a change stays on this phone, as every note does.

## Your notes on every phone

Each phone that you sign in on shows all your notes, as in Apple Notes. It gets the notes from your space: notes from your other phones, your Relay Everything page on a computer, email, Claude Code, Codex, your AI apps and the web API. A new phone gets all your old notes the first time.

New notes and changes come in when you open the app, when you come back to it, when you pull down the list, and every hour in the background. A note from somewhere else shows where it came from, under its title in the list and at the top of the note.

Notes go first. Each time, the phone sends your notes, then gets the new notes. Only then does it send [health](../health/), [places](../location/), the [calendar](../calendar/) and [photos](../photos/). A note that you write while they send goes before the rest. If a health, place, calendar or photo upload fails, your notes still go and come in. That data waits on the phone and goes on a later sync.

- **Edit anywhere.** Change a note on one phone, and your other phones, your page and your AI get the new words at their next sync. Each of your webhooks gets one [`note.updated`](../../connections/your-database/#noteupdated) message.
- **Delete anywhere.** Delete a note on one phone, and it goes from your other phones at their next sync, and from your page and your AI: [Delete a note](#delete-a-note). A note open on another phone stays until you leave it, then goes.
- **The newer change wins.** If two phones change the same note before they sync, the change made later stays on every phone and on your page, even when the older change arrives last.
- **Files on tap.** A note from somewhere else lists its files by name and size. Tap one to download it and open it. Only that file downloads, so the phone uses no space or data for files you never open. You add files only to the notes you wrote on this phone.
- **Voice recordings stay on their phone.** A voice note from another phone shows its words with no recording. An older recorded note's recording downloads and opens on tap, as a file does.
- **Signing out** with **Sign out** on the [Account](../settings/#account) page deletes the notes from somewhere else, and their files, from this phone. The notes that you wrote on this phone stay.

Signed out, the phone gets no notes and makes no network call. Notes it got before stay until you sign out. With **My own webhook**, the phone sends only to your webhook and gets no notes. To get your notes on every phone and keep your own database too, sign in to Relay Everything and add your webhook on your Relay Everything page: your server sends every note and change from every phone to it.

## Search your notes

1. Tap **Search**, at the bottom of Home or of a folder.
2. Type a word. The list shows only the notes with that word in their words, their place or their file names. Upper and lower case are the same. On Home, search finds notes in every folder. In a folder, it finds only that folder's notes.
3. Tap **Cancel** to see Home or all the folder's notes again.

Search reads only the notes on this phone, so it works with no signal and sends nothing. With no match, the list says *No notes with "<your words>"*.

## The gear and your Relay Everything page

Tap the round gear button at the top right of Home to open [Settings](../settings/).

To open your Relay Everything page, open Settings, tap the first row with your email, then tap **Open your Relay Everything page**. It shows while the phone sends to your Relay Everything server. It opens `<your-relay-server>/` in the phone's browser. Sign in with your email. The notes from all your devices are there. [Account](../settings/#account)

On a computer, open the same address. The page is the same app as on your phone, sized for a computer: you read, write, change and delete your notes there. [On a computer](../on-a-computer/)

## Write a note

1. Tap **New note**, the round green button at the bottom right. A short tap opens a new note. A hold records a voice note: [Talk a note](#talk-a-note).
2. Type the note. The keyboard opens at once. The first line is the note's title.
3. Tap **‹** to go back. The phone keeps the note as you type, so you do not save it.

The note shows at once, with or without a signal. With **Pin notes to where I am** on, it keeps where you are; the pin follows when the phone has a fix. With sending on, the note also goes to your server. If the phone sends a note two times, for example after it lost the server's answer, your server keeps it one time.

## Add photos and files

A note can hold photos, screenshots, PDFs and other files of any kind.

1. Tap **New note**.
2. Type the note, or leave it empty: a note can be only files.
3. Tap **Add photo or file**, the paperclip, and pick photos or files from the phone. Each one shows under the words, with its name and size.
4. Tap **‹** to go back.

You can add a file to a note later too: open the note and tap the paperclip. With sending on, a file that you add to a sent note goes to your server after the change.

A note holds up to 10 files, each up to 25 MB. The app refuses a file over 25 MB, or an eleventh file, with a message, and keeps the rest.

In your notes, the first picture shows small at the right of the note's row. On the note's own page, each picture shows full width, and another file shows as a row with its name and size. Tap a file to open it.

Where the files go:

- **On this phone**, always. iPhone backups keep them, because a file you added may be nowhere else. Android cloud backup leaves them out, because it holds at most 25 MB for an app.
- **In your space**, only with sending on. Each file goes after its note, sealed with your space's own key. When you turn sending on, [**Send them**](../../start/connect-a-phone/) sends the files of earlier notes too. [Privacy](../../privacy/)
- **On your Relay Everything page**, a picture shows in its note, and another file shows as a row with its name and size: click it to download it. [On a computer](../on-a-computer/#add-photos-and-files)
- **To your webhooks**, each file after its note, with its bytes: [Your own database](../../connections/your-database/#notefile). A receiver that refuses a file as too large skips it, and the file stays in your space.

[Shortcuts](../shortcuts/) can also add a note with files, with no tap in the app.

To keep a web page, a photo or a file from another app, use its share button: [Share from any app](../share/). A shared note has no place.

## Talk a note

Hold **New note**: an amber circle fills round it in half a second, and the phone buzzes. Until your first voice note, a tip above the button says **Hold to talk**. Let go, and talk: the phone keeps listening on its own full screen, with bars that move with your voice. Tap anywhere on the screen to save, or tap the **X** at the top right to keep nothing. The phone writes the words itself. [Voice notes](../voice-notes/)

## The sync state

The line under the **Home** title gives the sync state, such as *Synced*. Under a folder's name, it also gives how many notes the folder holds, such as *5 notes · Synced*. With sending on, a small dot is beside the state, and **Sync now**, a small ↻ button, follows it. Tap **Sync now** to sync now. You can also tap the state, or pull Home or a folder down: each does the same. The ↻ turns while the phone syncs. If the phone is set to reduce motion, it stays still. With sending off, **Sync now** does not show.

| State | Dot | What it means |
|---|---|---|
| **On this phone** | No dot | You are signed out. Your notes stay on this phone, and the app sends nothing. [Connect a phone](../../start/connect-a-phone/) to sign in. |
| **Synced** | Green, still | Your server has all the notes from this phone. |
| **Syncing** | Amber, pulses | The phone sends and gets notes now. It shows only for notes: health, places, the calendar and photos can still send after it ends. If the phone is set to reduce motion, the dot stays still. |
| **2 waiting** | Hollow | Notes made with no signal. They show **Waiting to send** and go on the next sync. |
| **Offline** | Hollow | The phone can not reach your server. You lose nothing. |
| **Key refused** | Red | The server refused this phone's key. [Connect the phone](../../start/connect-a-phone/) with a new key. |
