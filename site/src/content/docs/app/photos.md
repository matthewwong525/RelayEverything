---
title: Photos
description: Send the new photos you take to your Relay Everything server, so your AI can see them.
---

Relay Everything can send the photos you take on your phone to your own space, with when and where you took them. Your AI then finds them and looks at them through the [AI connector](../../connections/connect-your-ai/), for example: *show me the photos from the trip to Lisbon*. Relay Everything adds no captions or tags.

**Photos** sends each new photo by itself, with no note. To keep a photo as a note, with your own words, add it to a note: [Add photos and files](../your-notes/#add-photos-and-files), or share it from another app: [Share from any app](../share/). A photo on a note is one of the note's files, and goes where your notes go.

## Turn it on

1. Open **Settings**.
2. Turn on **Send my notes**, if it is off, and pick **Relay Everything**: [Connect a phone](../../start/connect-a-phone/). Photos work only with sending on, and the app reads no photo while it is off.
3. Turn on **Photos**.
4. Allow the app to read your photos. On Android, also allow it to read the place in your photos.

The phone asks for photo access only when you turn on **Photos**. If you say no, the switch stays off: allow photos for Relay Everything in the phone's own Settings, then try again.

## Photos go only to Relay Everything

Photos go only to your Relay Everything server, never to a webhook, because each photo carries where you took it. When the phone sends to [your own webhook](../../connections/your-database/#send-from-the-phone) instead, **Photos** and **Send photos on mobile data** are not in **Settings**, and the app reads and sends no photo. If you move sending to your webhook, the copies that did not go yet are deleted. Photos on a note still go to your webhook, as the note's files.

## Only new photos

The app sends only the photos you take after you turn on **Photos**. It never sends the photos from before. Videos stay on the phone. Screenshots and Live Photos go as still photos.

On an iPhone with **Limited** photo access, the app sends only the new photos you picked for it. iOS shows it no others.

## Wi-Fi or mobile data

Photos wait for Wi-Fi. To send them on mobile data too, turn on **Send photos on mobile data** in **Settings**. It is off at first, and works only while **Photos** is on.

A photo that waits for Wi-Fi does not hold back your notes, health or places: they go as before.

## When it sends

The app looks for new photos each time you open it, and about once an hour while it can run. On an iPhone, it also looks each time Apple Health or a new place wakes the closed app, after it sends the readings and points. iOS runs background work when it chooses, so a photo can arrive some hours late. Open the app to send at once.

Each photo is kept once, however often the phone sends it.

## What the phone sends

For each photo, the phone sends:

- **A JPEG copy**, at most 1,600 pixels on its long side, which is the most an AI uses. The copy is new, so it has no EXIF block from the original.
- **The time you took it.**
- **The place you took it**, when the photo has one.

Each copy is at most 3 MB. The original stays on your phone, and the app never deletes it. [Privacy](../../privacy/) says where your server keeps each photo.

## Turn it off

Turn off **Photos** in **Settings**. The phone stops sending, and deletes the copies that did not go yet. Turning off **Send my notes** also stops photos. The photos already sent stay on your server.

## Delete all photos

1. Open your Relay Everything page, and sign in: [Sign up](../../start/sign-up/).
2. On the **Photos** card, click **Delete all photos**, then confirm.

It deletes every photo your phones sent, and your AI can't see them any more. Your ring recordings, notes, health and places stay. You can't undo it. The card shows how many photos your space holds, but not the photos.
