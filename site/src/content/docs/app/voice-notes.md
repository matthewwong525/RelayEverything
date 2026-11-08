---
title: Voice notes
description: Hold New note in the Relay Everything app, let go, talk, and tap anywhere to save. The phone writes your words itself, and your voice never leaves the phone.
---

Hold **New note** in the Relay Everything app, let go, talk, and tap anywhere to save. The note shows at once, and its words fill in a few seconds later. The phone writes the words itself, with no signal and no server. Your voice never leaves the phone.

## Make a voice note

1. Hold **New note**, the round green button at the bottom of your notes, for half a second. The phone buzzes, and the button turns into an amber mic.
2. Let go. The phone keeps listening. A card shows **Listening**, a clock, and *Tap anywhere to save.*
3. Talk.
4. Tap anywhere on the screen to save. To throw the note away, tap **Cancel** on the card.

A tap shorter than half a second opens the **New note** page to type, and records nothing.

The note shows **Voice** and **Writing the words…**, then its words. A note ends by itself after 5 minutes.

The first time you hold **New note**, the phone asks for the microphone. If you said no, allow the microphone for Relay Everything in the phone's settings.

## When the words do not come

If the phone can not write the words, or they take longer than 2 minutes (or the recording's length, if it is longer), the note shows **The words did not come** in your notes. Open it, and it says **The words did not come. Your recording is safe.** The app tells you once. The note keeps its recording, and **Play** still works.

Tap **Try again** on the open note to write the words again. The next time you open the app, it also tries again by itself.

## Get the speech model

Voice notes need a speech model: a 57 MB file, one time. The first time you hold **New note**, the app asks before it gets it, and records nothing:

1. Tap **Get it**. Tap **Not now** to get nothing.
2. A card on your notes shows how much has come. You can type notes while it comes.
3. When it is done, hold **New note** again.

The phone gets the model from [whisper.cpp's page on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp), and checks it against a fixed checksum. A file that does not match is deleted. If the download stops, tap **Try again**: it goes on from where it stopped.

The model is whisper.cpp's English base model, so voice notes are in English. The phone does not back it up to iCloud or Google.

To free the space, tap **Remove** in [Settings](../settings/#voice-notes). The next voice note asks to get it again.

## No speech, no note

The app keeps nothing from:

- A press on **New note** shorter than half a second. It opens the **New note** page, and a bump in your pocket makes no voice note.
- A note you throw away with **Cancel**.
- A recording with no words in it. The app says **No speech heard**.

The Relay Everything ring uses the same rule: [How the ring works](../../ring/how-it-works/#against-bumps).

## Play a note back

Tap a voice note in your notes to open it, then tap **Play** to hear it. The recording stays on this phone.

The phone does not back up recordings to iCloud or Google. When you move to a new phone, the recordings stay behind: your voice notes come with their words, and **Play** says the recording is not on this phone.

## Where your voice goes

| What | Where |
|---|---|
| The recording | This phone only. It is never sent, and phone backups leave it out. |
| The words | This phone. With sending on, they go to your Relay Everything server, the same as a typed note. |

On your server and in other places that read it, a voice note shows as a typed note. A note goes to your server only when it has its words. [Privacy](../../privacy/)
