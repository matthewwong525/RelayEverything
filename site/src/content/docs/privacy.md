---
title: Privacy
description: What Relay Everything keeps, where it keeps it, and how to turn each part off.
---

Relay Everything keeps your notes on your phone. When you turn on sending, it keeps your notes, health, calendar, places and photos in your own space on a Relay Everything server, or the phone sends them straight to [your own webhook](../connections/your-database/#send-from-the-phone), and none of them reach Relay Everything. A photo you share into a note is a file on that note. Your server sends them on only to the webhooks you add: notes to each one, and health, calendar, places and photos only to those you tick them for. It answers only the AI apps and services you connect and the API keys you make, each only when it asks. This website holds none of them.

## What is kept, and where

| What | Where | Sent when |
|---|---|---|
| Typed notes, with their pin | The phone's own storage, always | Never, while sending is off |
| Typed notes, with their place | Your space on your Relay Everything server | With sending on: each time you save a note. Notes from before go only if you tap **Send them**. |
| Files on a note: photos, PDFs and other files | The phone's own storage, always. iPhone backups keep them; Android cloud backup leaves them out. With sending on, also your space's folder of the file store, sealed. | With sending on: after their note. Files of earlier notes go only if you tap **Send them**. |
| Notes you share from another app, with their files | The phone's own storage, always, with no place | With sending on: when you tap **Save** on the share card, or the next time the app opens |
| Voice notes from the app: the recording | The phone's own storage, only. iCloud and Google backups leave it out. | Never |
| Voice notes from the app: the words | The phone's own storage; with sending on, also your space on your Relay Everything server | The same as a typed note, once the phone has written the words |
| Ring notes: the words and the recording | Your Relay Everything server: the words in your space, the recording sealed in your folder of its file store | Not now. Ring notes already in your space stay. The Relay Everything ring will send through the phone app when it is ready. |
| Health: steps, heart rate, sleep with each night's stages, workouts with their kind, distance and calories, weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle, mindful minutes and water, only the types you allow | Your space on your Relay Everything server | On open and every hour, with sending and **Health** on. The first time, the last 90 days. |
| Calendar events: title, times, place, notes, link, calendar name and people, from the calendars you leave on | Your space on your Relay Everything server | On open and with the hourly round, with sending and **Calendar** on. The first time, 90 days back and 90 days ahead; then only changes. |
| Location history: a point each 100 m you move | Your space on your Relay Everything server | With sending and **Location history** on, unless you pick **Only stays and trips** |
| Stays and trips: where you stayed, with its name, street and times, and how you moved, how far and how long | The phone works them out itself, and keeps only the one you are in now. Then your space on your Relay Everything server. | With sending and **Location history** on, unless you pick **Only points**: [Stays and trips](../app/location/#stays-and-trips) |
| Photos: a small copy, with when and where you took it | Your Relay Everything server: the time and place in your space, the copy sealed in your folder of its file store | With sending and **Photos** on, only the photos you take after you turn it on: [Photos](../app/photos/) |
| Email notes: mail to your notes address, or to `notes@` from your sign-in email, with its files | Your space on your Relay Everything server, the files sealed. The server's list finds you by a fingerprint (an HMAC) of your address, and keeps the address itself to show it on your card. If your address leaks, [replace it](../app/email/#replace-your-address). | When the mail comes. On the way, the sender's mail service and Cloudflare can read it: [Email notes](../app/email/#what-is-sent). |
| Mail to `notes@` from an email with no account yet | The server, sealed with a key made from that email, which the server does not keep. It finds the mail by a fingerprint of the email. | Kept 30 days, then deleted. If that email signs up first, the mail becomes notes in its space. |
| Notes from your other phones, email, Claude Code and your AI apps, with each file's name and size | The phone's own storage, after a sync. A file comes to the phone only when you open it. | With sending on and Relay Everything picked: on open, on pull-down and every hour. Signing out deletes them from the phone: [Notes on every phone](../app/your-notes/#your-notes-on-every-phone). |
| The phone's key | The iPhone Keychain or the Android Keystore; the server keeps only its fingerprint | Never sent, except as the key's header |
| Your email | The server's list of accounts, to sign you in | When you sign up |
| Your sign-in | A cookie in your browser, for 30 days | With each visit to your Relay Everything page |
| A copy of what your server stores | [Your own database](../connections/your-database/), through a webhook you add | Notes always, with each file's name, type and size but not the file; health, calendar, location and photos only if you tick them for that webhook. Each photo goes with its picture, when and where you took it |
| Everything the phone sends, when you pick **Send to my own webhook instead** | Only [your own database](../connections/your-database/#send-from-the-phone), straight from the phone; nothing on your Relay Everything server | With sending on, the same as above: notes, then each file with its bytes; health, calendar, location and photos only with their switches on. Each photo goes with its picture, when and where you took it |
| Health, calendar, location and photos, when you pick **Only my own webhook** on the Account page | Only [your own database](../connections/your-database/#send-from-the-phone), straight from the phone; nothing new on your Relay Everything server. What went there before stays until you delete it. | With sending on and each switch on. Your notes still sync through Relay Everything: [Settings](../app/settings/#health-places-calendar-and-photos-only-to-your-webhook) |
| Your webhook's address and secret | The iPhone Keychain or the Android Keystore | Never sent: the secret signs each message |

With sending off, the app makes no network call, reads no health data, no calendar and no photos, and keeps no location history. The one exception is the speech model for voice notes, and only after you tap **Get it**. The same is true when a shortcut adds a note: [Shortcuts](../app/shortcuts/#what-is-sent) follow your sending setting, and **Get notes** reads only the phone. The share card also follows it: with sending off it makes no network call: [Share from any app](../app/share/#what-is-sent).

## Who can see what

Each person's data is in their own space: a separate store that holds only that person's notes, health, calendar events, places, photos, chats, devices and webhooks. One shared list holds only who has an account, how they sign in, and a fingerprint of each key.

- **You** see your own space on your Relay Everything page, after you sign in.
- **Your devices** add data to your space. A phone's key also reads your notes and their files, and changes or deletes any note, so each signed-in phone shows all your notes. It can't read your health, calendar, places or photos, and can only add photos, not count or delete them. A chat key reads nothing. If you lose a phone, turn off its key on your Relay Everything page at once: [Keys](../api/keys/#make-list-and-turn-off-keys).
- **Your other phones** get your notes only while they are signed in with sending on and Relay Everything picked. A phone that sends to your own webhook gets none.
- **Your AI apps** read only your space, and add notes to it, only after you connect them: [Connect your AI](../connections/connect-your-ai/). Only your page and your AI apps can open a photo.
- **Your own scripts and services** read your space and add notes through the web API, only with an API key you made or after you connect them: [Connect a service](../api/connect-a-service/).
- **Your webhooks** send only your data, to the addresses you add. They send photos from the **Photos** switch only to a webhook you tick **Photos** for.
- **No one else.** The server opens a space only for the person who signed in, or for that person's own key or AI app. There is no screen, route or tool for the server's owner to open another person's space. [The code is public](https://github.com/matthewwong525/RelayEverything), and a test fails if such a way in is added.

Each recording, each file on a note and each photo is in your own folder of the server's file store, sealed with a key that is kept in your space. The file store alone, as in the Cloudflare dashboard, shows only sealed bytes. Only your own sign-in opens a file on your Relay Everything page, and only your own phones' keys open one in the app.

**The limit:** the owner of the Cloudflare account that runs a server could change its code to read a space. Only encryption on the phone stops that, and Relay Everything does not have it yet. On [your own server](../start/run-your-own/), that owner is you.

## Delete your account

Click **Delete my account** on your Relay Everything page, and type your email to confirm. It deletes your space, your recordings, the files on your notes, your photos, your keys, your notes address, your sign-ins and your connected AI apps. You can't undo it. Your notes stay on your phone.

## What is not kept

- The Relay Everything app has no ads and no analytics. It sends your notes, their files, health, calendar events, places and photos only to the places you pick, and only with sending on. Your notes go to your Relay Everything server or your own webhook. Your health, calendar events, places and photos go where your notes go, or only to your own webhook: [Settings](../app/settings/#health-places-calendar-and-photos-only-to-your-webhook). Your server sends them on only to your webhooks, and sends a note's file's name, type and size, never the file.
- To name a place, such as a street, the phone uses its own address lookup from Apple or Google, only with sending on. That lookup gets the place's coordinates, not the note. With sending off, a pinned note shows **Pinned**.
- To name a stay, the phone reads your calendar on the phone, then asks Apple Maps (on an iPhone) and the address lookup one time for that stay, only with sending on. They get the stay's coordinates, not your history. A calendar event's place goes to the address lookup too, to find where it is.
- The phone reads motion, such as walking or driving, only to tell how you moved on a trip. Motion stays on the phone: only the trip's mode is sent. The app reads no steps from motion: steps come only from **Health**.
- The phone writes a voice note's words itself. No speech service on a network hears your voice.
- The speech model comes from [whisper.cpp's page on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp), one time, after you tap **Get it**. Hugging Face sees the phone's internet address, the same as any download. It gets no note, no recording and no key.
- This website keeps no cookies and counts no visits. It is static pages, and it can't reach your server.

## Turn each part off

| Part | How |
|---|---|
| Everything sent | Tap **Sign out**, or **Stop sending** for your own webhook, on the app's [Account](../app/settings/#account) page. Health, the calendar, location and photos stop, and what of them did not go yet is deleted. |
| A note | [Delete it](../app/your-notes/#delete-a-note) with a swipe or **⋯** → **Delete**. With sending on, your server deletes the note, its files and its recording too, and each webhook gets `note.deleted`. A copy your webhook already saved stays in your own database until your receiver deletes it. |
| Voice notes | Do not tap **Get it**, or tap **Remove** in Settings to delete the speech model. Delete a recording by deleting its note, or by removing the app. |
| Pins on typed notes | Turn off **Pin notes to where I am** in Settings. |
| Location history | Turn off **Location history** in the app's **Location** folder. |
| Photos | Turn off **Photos** in the app's **Photos** folder: the copies that did not go yet are deleted. To delete the photos already sent, click **Delete all photos** on your Relay Everything page: [Photos](../app/photos/#delete-all-photos). |
| Health | Turn off **Health** in the app's **Health** folder, and take back the permission in Apple Health or Health Connect. To keep one type back, such as cycle, turn off only that type there. |
| Calendar | Turn off **Calendar** in the app's **Calendar** folder, or one calendar under it, and take back the permission in the phone's settings. A calendar you turn off is removed from your space at the next send. |
| One phone | Tap **Sign out** on the app's **Account** page, or click **Turn off** beside it on your Relay Everything page: [Keys](../api/keys/#make-list-and-turn-off-keys). |
| Email notes | Don't give out your notes address. If it leaks, click **New address** on the **Email** card: [Email notes](../app/email/#replace-your-address). |
| A webhook to your database | **Pause** or **Remove** it on the Relay Everything page: [Your own database](../connections/your-database/). |

Turning a part off stops new data. Data already in your space stays there until you [delete your account](#delete-your-account), or, for photos, click **Delete all photos**. Your notes stay on your phone.
