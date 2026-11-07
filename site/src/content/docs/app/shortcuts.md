---
title: Shortcuts
description: Add notes and files, get your notes, and start a voice note from Apple Shortcuts, Siri, automations and the Action button.
---

The Relay Everything app gives Apple Shortcuts three actions: **Add a note**, **Get notes** and **Start a voice note**. Use them in a shortcut, with Siri, in Spotlight, on the Action button, and in automations that run on their own, such as *when I get to work*.

The actions need the Relay Everything app on an iPhone with iOS 16 or later. On iOS 15 the app works as before, and Shortcuts shows no Relay Everything actions. The actions need no key. Shortcuts on a Mac and on Android are not available.

## Find the actions

1. Open the **Shortcuts** app.
2. Make a new shortcut, or open one, and tap **Add Action**.
3. Tap **Apps**, then **Relay Everything**.

You can also say *Add a note to Relay Everything* to Siri.

## Add a note

**Add a note** keeps a note with words, files, or both. Give it typed words, a photo, a screenshot, a PDF, a link, the clipboard, or the output of the step before. It runs without opening the app.

- The note is kept on the phone at once. With **Pin notes to where I am** on, it keeps where you are, the same as a note you type.
- A note holds up to 10 files, each up to 25 MB. The action refuses a file over 25 MB, or an eleventh file, with a message, and keeps the rest. [Notes](../your-notes/#add-photos-and-files)
- With no words and no files, the action stops with a message and keeps nothing.
- The action gives the new note back, so the next step can use it.

If the app takes more than 20 seconds to answer, the action says *Saved. It shows when you open Relay Everything.* The note is safe. It shows in your notes, and goes on to your server, the next time you open the app.

## Get notes

**Get notes** gives your notes to the next step, newest first. Pick any of:

| Choice | Example |
|---|---|
| **Limit** | The last 5 notes |
| **Words** | Notes that say *groceries* |
| **Since** | Notes from today |

Each note gives its words, time, place, files, and whether it is a voice note. **Get notes** reads only the notes on this phone. It sends nothing and asks no server.

## Start a voice note

**Start a voice note** opens the app and starts to record at once. It shows the same **Listening** card as a hold on **New note**. Talk, then tap anywhere on the screen to save the note, or tap **Cancel** to keep nothing. The phone writes the words itself. [Voice notes](../voice-notes/)

With no speech model on the phone yet, the app asks to get it first. [Get the speech model](../voice-notes/#get-the-speech-model)

## What is sent

The actions follow your **Send my notes** setting in [Settings](../settings/):

| Sending | Add a note | Get notes | Start a voice note |
|---|---|---|---|
| Off | Kept on the phone. The app makes no network call. | Reads the phone. Sends nothing. | Kept on the phone. |
| On | Kept on the phone, and sent to your space at once, with its files. | Reads the phone. Sends nothing. | Kept on the phone; its words go to your space. |

Your server sends a note on to your webhooks with each file's name, type and size, not the file. When the phone sends to [your own webhook](../../connections/your-database/#send-from-the-phone), the note and its files go there, not to your space. [Privacy](../../privacy/)

## Recipes

Each recipe uses the Shortcuts app. An automation is under **Automation** at the bottom of the Shortcuts app. For each automation, pick **Run Immediately**, so it runs without asking.

### A note when you arrive at work

1. In **Automation**, tap **+**, then **Arrive**.
2. Tap **Location**, pick your work, and tap **Done**.
3. Pick **Run Immediately**, then **Next**.
4. Tap **New Blank Automation**, and add **Add a note** from Relay Everything.
5. Type *At work* in its words.

### A note with each screenshot

1. Make a new shortcut, and name it *Screenshot to Relay Everything*.
2. Add **Take Screenshot**.
3. Add **Add a note**, and set its files to the **Screenshot** from the step before. Type words too, if you like.
4. Open the iPhone's **Settings**, then **Accessibility**, **Touch**, **Back Tap**. Pick **Double Tap**, then the shortcut.

Tap the back of the phone two times. The screenshot goes into a note.

### Today's notes by email each evening

1. In **Automation**, tap **+**, then **Time of Day**.
2. Set **9:00 PM**, **Daily**, and **Run Immediately**, then tap **Next**.
3. Tap **New Blank Automation**.
4. Add **Date**, then **Adjust Date**, and pick **Get Start of Day**.
5. Add **Get notes**, and set **Since** to the **Adjusted Date**.
6. Add **Send Email**. Put your address in **To**, and the **Notes** in the message.

The email holds each note from today. No server is asked: the notes come from the phone.

### A note when you tap an NFC tag

1. In **Automation**, tap **+**, then **NFC**.
2. Tap **Scan**, and hold the phone to the tag, for example on the cat's food box. Name the tag.
3. Pick **Run Immediately**, then **Next**.
4. Tap **New Blank Automation**, and add **Add a note**.
5. Type *Fed the cat* in its words.

### A voice note from the Action button

On an iPhone with an Action button:

1. Open the iPhone's **Settings**, then **Action Button**.
2. Swipe to **Shortcut**, and tap **Choose a Shortcut**.
3. Pick **Relay Everything**, then **Start a voice note**.

Press the Action button, talk, and tap anywhere on the screen to save.
