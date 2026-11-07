---
title: Privacy
description: What Relay Everything keeps, where it keeps it, and how to turn each part off.
---

Relay Everything keeps your notes on your phone. When you turn on sending, it keeps your notes, health, calendar and places in your own space on a Relay Everything server. Your server sends them on only to the webhooks you add: notes to each one, and health, calendar and places only to those you tick them for. It answers only the AI apps and services you connect and the API keys you make, each only when it asks. This website holds none of them.

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
| Health: steps, heart rate, sleep, workouts, weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle, mindful minutes and water, only the types you allow | Your space on your Relay Everything server | On open and every hour, with sending and **Health** on. The first time, the last 90 days. |
| Calendar events: title, times, place, notes, link, calendar name and people, from the calendars you leave on | Your space on your Relay Everything server | On open and with the hourly round, with sending and **Calendar** on. The first time, 90 days back and 90 days ahead; then only changes. |
| Location history: a point each 100 m you move | Your space on your Relay Everything server | With sending and **Location history** on |
| The phone's key | The iPhone Keychain or the Android Keystore; the server keeps only its fingerprint | Never sent, except as the key's header |
| Your email | The server's list of accounts, to sign you in | When you sign up |
| Your sign-in | A cookie in your browser, for 30 days | With each visit to your Relay Everything page |
| A copy of what your server stores | [Your own database](../connections/your-database/), through a webhook you add | Notes always, with each file's name, type and size but not the file; health, calendar and location only if you tick them for that webhook |

With sending off, the app makes no network call, reads no health data and no calendar, and keeps no location history. The one exception is the speech model for voice notes, and only after you tap **Get it**. The same is true when a shortcut adds a note: [Shortcuts](../app/shortcuts/#what-is-sent) follow your sending setting, and **Get notes** reads only the phone. The share card also follows it: with sending off it makes no network call: [Share from any app](../app/share/#what-is-sent).

## Who can see what

Each person's data is in their own space: a separate store that holds only that person's notes, health, calendar events, places, chats, devices and webhooks. One shared list holds only who has an account, how they sign in, and a fingerprint of each key.

- **You** see your own space on your Relay Everything page, after you sign in.
- **Your devices** only add data to your space. A phone's key or a chat key can't read your notes, health, calendar or places back: [Keys](../api/keys/).
- **Your AI apps** read only your space, and add notes to it, only after you connect them: [Connect your AI](../connections/connect-your-ai/).
- **Your own scripts and services** read your space and add notes through the web API, only with an API key you made or after you connect them: [Connect a service](../api/connect-a-service/).
- **Your webhooks** send only your data, to the addresses you add.
- **No one else.** The server opens a space only for the person who signed in, or for that person's own key or AI app. There is no screen, route or tool for the server's owner to open another person's space. [The code is public](https://github.com/matthewwong525/RelayEverything), and a test fails if such a way in is added.

Each recording and each file on a note is in your own folder of the server's file store, sealed with a key that is kept in your space. The file store alone, as in the Cloudflare dashboard, shows only sealed bytes. Only your own sign-in opens a file on your Relay Everything page.

**The limit:** the owner of the Cloudflare account that runs a server could change its code to read a space. Only encryption on the phone stops that, and Relay Everything does not have it yet. On [your own server](../start/run-your-own/), that owner is you.

## Delete your account

Click **Delete my account** on your Relay Everything page, and type your email to confirm. It deletes your space, your recordings, the files on your notes, your keys, your sign-ins and your connected AI apps. You can't undo it. Your notes stay on your phone.

## What is not kept

- The Relay Everything app has no ads and no analytics. It sends your notes, their files, health, calendar events and places only to your Relay Everything server, and only with sending on. Your server sends them on only to your webhooks, and sends a file's name, type and size, never the file.
- To name a place, such as a street, the phone uses its own address lookup from Apple or Google, only with sending on. That lookup gets the place's coordinates, not the note. With sending off, a pinned note shows **Pinned**.
- The phone writes a voice note's words itself. No speech service on a network hears your voice.
- The speech model comes from [whisper.cpp's page on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp), one time, after you tap **Get it**. Hugging Face sees the phone's internet address, the same as any download. It gets no note, no recording and no key.
- This website keeps no cookies and counts no visits. It is static pages, and it can't reach your server.

## Turn each part off

| Part | How |
|---|---|
| Everything sent | Turn off **Send to Relay Everything** in [Settings](../app/settings/). Health, the calendar and location stop, and what of them did not go yet is deleted. |
| Voice notes | Do not tap **Get it**, or tap **Remove** in Settings to delete the speech model. Delete a recording by removing the app. |
| Pins on typed notes | Turn off **Pin notes to where I am** in Settings. |
| Location history | Turn off **Location history** in Settings. |
| Health | Turn off **Health** in Settings, and take back the permission in Apple Health or Health Connect. To keep one type back, such as cycle, turn off only that type there. |
| Calendar | Turn off **Calendar** in Settings, or one calendar under it, and take back the permission in the phone's settings. A calendar you turn off is removed from your space at the next send. |
| One phone | Tap **Disconnect this phone** in Settings, or click **Turn off** beside it on your Relay Everything page: [Keys](../api/keys/#make-list-and-turn-off-keys). |
| A webhook to your database | **Pause** or **Remove** it on the Relay Everything page: [Your own database](../connections/your-database/). |

Turning a part off stops new data. Data already in your space stays there until you [delete your account](#delete-your-account), and your notes stay on your phone.
