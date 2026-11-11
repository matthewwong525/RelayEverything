---
title: Share from any app
description: Keep a web page, a photo, a PDF or a piece of text as a note from the share button of any app on iPhone or Android.
---

Relay Everything is in the share list of every app. Share a web page, text, photos or a file, add words if you like, and tap **Save**. You stay in the app you share from.

## Share on iPhone

1. In any app, tap the share button.
2. Tap **Relay Everything** in the row of apps. If it is not there, swipe to the end, tap **More**, and turn on **Relay Everything**.
3. Read what you share on the card. Add words in **Add words** if you like.
4. Tap **Save**. The card closes.

The card looks like the app: the paper color, a card that shows what you share, a green **Save** and the Inter font, in light and dark. It is the same as the card on Android, and it works with no network.

Open the app once after you install it or update it, before the first share.

## Share on Android

1. In any app, tap **Share**.
2. Tap **Relay Everything**.
3. Add words in **Add words** if you like.
4. Tap **Save**. The card closes.

## What each item becomes

| You share | The note |
|---|---|
| A web page | Your words, then the page's title and link |
| Text | Your words, then the text |
| Photos or a video | Your words, and the photos or video as files |
| A PDF or another file | Your words, and the file |

A photo you share becomes a file on its note, and goes where your notes go. To send each new photo you take, with no note, so your AI can see it, turn on **Photos** instead: [Photos](../photos/).

A shared note has no place, even with **Pin notes to where I am** on: you shared it, you did not make it there. In your notes, it shows as a note you wrote.

## The limits

A note holds up to 10 files, each up to 25 MB, the same as a note you write: [Add photos and files](../your-notes/#add-photos-and-files). The card says what it leaves out:

- *A note holds up to 10 files. 2 files were not added.* for 12 photos.
- *clip.mov is over 25 MB, so it was not added.* for a large video. With nothing else to keep, **Save** stays off until you add words.

## What is sent

The card follows your sign-in on the [Account](../settings/#account) row in Settings. Signed out, sending is off. The last line of the card tells you which:

| Sending | The card says | What happens |
|---|---|---|
| Off | *Kept on this phone. Sending is off.* | The note stays on the phone. The card makes no network call. |
| On | *Sending…*, then *Sent* | The note and its files go to your space before the card closes. |
| On, with no signal | *Kept. It sends when you open Relay Everything.* | The note is safe on the phone. The app sends it the next time it opens or syncs. |
| On, to [your own webhook](../../connections/your-database/#send-from-the-phone) | On iPhone: *Kept. It sends when you open Relay Everything.* | The iPhone card only keeps the note. The app sends it to your webhook the next time it opens or syncs. Android's card sends it at once. |

If the card sends a note and the app sends it again, your server keeps it one time. [Privacy](../../privacy/)
