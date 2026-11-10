---
title: Shortcuts
description: Add notes and files, take a note with Siri, get your notes, and start a voice note from Apple Shortcuts, automations and the Action button.
---

The Relay Everything app gives Apple Shortcuts three actions: **Add a note**, **Get notes** and **Start a voice note**. Use them in a shortcut, with Siri, in Spotlight, on the Action button, and in automations that run on their own, such as *when I get to work*.

The actions need the Relay Everything app on an iPhone with iOS 16 or later. On iOS 15 the app works as before, and Shortcuts shows no Relay Everything actions. The actions need no key. Shortcuts on a Mac and on Android are not available.

## Find the actions

1. Open the **Shortcuts** app.
2. Make a new shortcut, or open one, and tap **Add Action**.
3. Tap **Apps**, then **Relay Everything**.

You can also tell Siri. [Take a note with Siri](#take-a-note-with-siri)

## Add a note

**Add a note** keeps a note with words, files, or both. Give it typed words, a photo, a screenshot, a PDF, a link, the clipboard, or the output of the step before. It runs without opening the app.

- The note is kept on the phone at once. With **Pin notes to where I am** on, it keeps where you are, the same as a note you type.
- A note holds up to 10 files, each up to 25 MB. The action refuses a file over 25 MB, or an eleventh file, with a message, and keeps the rest. [Notes](../your-notes/#add-photos-and-files)
- With no words and no files, the action asks *What's the note?* and keeps your answer. In an automation that runs on its own, no one can answer, so the action stops with a message and keeps nothing.
- The action gives the new note back, so the next step can use it.

The action's line reads *Add Note with Files to Relay Everything*. Tap **Note** to type its words, and **Files** to give it a file from a step before. A shortcut you made when the line said *Words* keeps its words.

### A recording becomes a voice note

Give **Add a note** one recording, such as the **Recorded Audio** from **Record audio**, and the note is a voice note. It shows **Voice** and **Play**, and the phone writes its words itself, as for a voice note you hold **New note** for. [Voice notes](../voice-notes/)

- **Your words go first.** Give words with the recording, such as *Note @ 7:07 PM*, and the note starts with them. The written words of the recording follow on the next line.
- **The words are written in the open app.** When the app is closed, the voice note waits on the phone, and the phone writes its words the next time you open Relay Everything.
- **No speech, no new words.** A recording with no speech keeps your words and the recording. With no words of yours either, the note is not kept, and the app says **No speech heard**.
- **Other files stay files.** A recording given with other files, or a recording the phone can not read, is kept as a plain file.

With sending on, the voice note goes to your space once its words are written. The recording stays on the phone.

If the app takes more than 20 seconds to answer, the action says *Saved. It shows when you open Relay Everything.* The note is safe. It shows in your notes, and goes on to your server, the next time you open the app.

### Take a note with Siri

Say the note to Siri, and Siri keeps it as a typed note. Siri knows a short name, so you can say *take a note in Relay*. The full name, Relay Everything, works too, and the app's name on your Home Screen stays Relay Everything.

- **On an iPhone with the new Siri** (iOS 27 with Apple Intelligence), say the note in one sentence: *Hey Siri, take a note in Relay, buy milk on the way home*. Siri asks nothing and says *Saved*.
- **On other iPhones**, say *Hey Siri, take a note in Relay*. Siri asks *What's the note?*. Say the note, and Siri says *Saved*.

*Hey Siri, add a note to Relay* and *Hey Siri, note in Relay* work too. If another app on your phone has the same short name, Siri asks which app. With sending on, the note goes to your space at once, as a typed note does.

## Get notes

**Get notes** gives your notes to the next step, newest first. Pick any of:

| Choice | Example |
|---|---|
| **Limit** | The last 5 notes |
| **Words** | Notes that say *groceries* |
| **Since** | Notes from today |

Each note gives its words, time, place, files, and whether it is a voice note. **Get notes** reads only the notes on this phone. It sends nothing and asks no server.

## Start a voice note

**Start a voice note** opens the app and starts to record at once, on the same full screen as a hold on **New note**. Talk, then tap anywhere on the screen to save the note, or tap the **X** at the top right to keep nothing. The note opens over the page that was open, and the phone writes the words itself. [Voice notes](../voice-notes/)

With no speech model on the phone yet, the app asks to get it first. [Get the speech model](../voice-notes/#get-the-speech-model)

## What is sent

The actions follow your sign-in on the [Account](../settings/#account) row in Settings. Signed out, sending is off:

| Sending | Add a note | Get notes | Start a voice note |
|---|---|---|---|
| Off | Kept on the phone. The app makes no network call. | Reads the phone. Sends nothing. | Kept on the phone. |
| On | Kept on the phone, and sent to your space at once, with its files. A recording's note goes once its words are written; the recording stays on the phone. | Reads the phone. Sends nothing. | Kept on the phone; its words go to your space. |

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

### A voice note from Record audio

1. Make a new shortcut, and name it *Voice note to Relay Everything*.
2. Add **Record audio**. Set **Start Recording** to **Immediately** if you like.
3. Add **Add a note** from Relay Everything.
4. Tap **Files**, and pick the **Recorded Audio** from the step before.
5. Tap **Note**, and type a label, such as *Note @*, then add the **Current Date**. Leave **Note** empty if you want only the written words.

Run the shortcut, talk, and tap **Done**. The note shows as a voice note that starts with your label, and its words follow when the app is open.

### A voice note from the Action button

On an iPhone with an Action button:

1. Open the iPhone's **Settings**, then **Action Button**.
2. Swipe to **Shortcut**, and tap **Choose a Shortcut**.
3. Pick **Relay Everything**, then **Start a voice note**.

Press the Action button, talk, and tap anywhere on the screen to save.
