---
title: Privacy
description: What Relay Everything keeps, where it keeps it, and how to turn each part off.
---

Relay Everything keeps your notes on your phone. When you turn on sending, it keeps your notes, health and places in your own space on a Relay Everything server. Your server sends them on only to the webhooks you add: notes to each one, and health and places only to those you tick them for. It answers only the AI apps and services you connect and the API keys you make, each only when it asks. This website holds none of them.

## What is kept, and where

| What | Where | Sent when |
|---|---|---|
| Typed notes, with their pin | The phone's own storage, always | Never, while sending is off |
| Typed notes, with their place | Your space on your Relay Everything server | With sending on: each time you save a note. Notes from before go only if you tap **Send them**. |
| Files on a note: photos, PDFs and other files | The phone's own storage, always. iPhone backups keep them; Android cloud backup leaves them out. With sending on, also your space's folder of the file store, sealed. | With sending on: after their note. Files of earlier notes go only if you tap **Send them**. |
| Voice notes from the app: the recording | The phone's own storage, only. iCloud and Google backups leave it out. | Never |
| Voice notes from the app: the words | The phone's own storage; with sending on, also your space on your Relay Everything server | The same as a typed note, once the phone has written the words |
| Ring notes: the words and the recording | Your Relay Everything server: the words in your space, the recording sealed in your folder of its file store | Each time you hold the ring and talk, through the Pebble app |
| Steps, heart rate, sleep and workouts | Your space on your Relay Everything server | On open and every hour, with sending and **Health** on |
| Location history: a point each 100 m you move | Your space on your Relay Everything server | With sending and **Location history** on |
| The phone's key | The iPhone Keychain or the Android Keystore; the server keeps only its fingerprint | Never sent, except as the key's header |
| Your email | The server's list of accounts, to sign you in | When you sign up |
| Your sign-in | A cookie in your browser, for 30 days | With each visit to your Relay Everything page |
| Your Google connection: your Google address, the permissions you gave, and Google's sign-in, sealed | Your space on your Relay Everything server | When you click **Connect Google** |
| A copy of what your server stores | [Your own database](../connections/your-database/), through a webhook you add | Notes always, with each file's name, type and size but not the file; health and location only if you tick them for that webhook |

With sending off, the app makes no network call, reads no health data, and keeps no location history. The one exception is the speech model for voice notes, and only after you tap **Get it**. The same is true when a shortcut adds a note: [Shortcuts](../app/shortcuts/#what-is-sent) follow your sending setting, and **Get notes** reads only the phone.

## Who can see what

Each person's data is in their own space: a separate store that holds only that person's notes, health, places, chats, devices and webhooks. One shared list holds only who has an account, how they sign in, and a fingerprint of each key.

- **You** see your own space on your Relay Everything page, after you sign in.
- **Your devices** only add data to your space. A phone's key or a chat key can't read your notes, health or places back: [Keys](../api/keys/).
- **Your AI apps** read only your space, and add notes to it, only after you connect them: [Connect your AI](../connections/connect-your-ai/).
- **Your own scripts and services** read your space and add notes through the web API, only with an API key you made or after you connect them: [Connect a service](../api/connect-a-service/).
- **Your webhooks** send only your data, to the addresses you add.
- **Your Google** is reached only after you connect it, only by your AI apps connected after that and your API keys: [Google](#google).
- **No one else.** The server opens a space only for the person who signed in, or for that person's own key or AI app. There is no screen, route or tool for the server's owner to open another person's space. [The code is public](https://github.com/matthewwong525/RelayEverything), and a test fails if such a way in is added.

Each recording and each file on a note is in your own folder of the server's file store, sealed with a key that is kept in your space. The file store alone, as in the Cloudflare dashboard, shows only sealed bytes. Only your own sign-in opens a file on your Relay Everything page.

**The limit:** the owner of the Cloudflare account that runs a server could change its code to read a space. Only encryption on the phone stops that, and Relay Everything does not have it yet. On [your own server](../start/run-your-own/), that owner is you.

## Google

When you [connect Google](../connections/google/), your space keeps your Google address, the permissions you gave, and Google's sign-in for Relay Everything, sealed with your space's own key. It keeps no email, event, file or contact. Each request from your AI app or API key goes to Google, and Google's answer goes back to that app or script only.

Relay Everything's use and transfer of information received from Google APIs to any other app will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements.

- Relay Everything uses your Google data only to answer the requests you or your connected apps and keys make.
- It does not use your Google data for ads, does not sell it, and does not use it to train AI models.
- No person at Relay Everything reads your Google data.
- Google's answer to an AI app goes to that app's company, under its own terms: [What leaves Relay Everything](../connections/connect-your-ai/#what-leaves-relay-everything).

To stop it, click **Disconnect** on the **Google** card. Relay Everything ends its sign-in at Google and deletes it.

## Delete your account

Click **Delete my account** on your Relay Everything page, and type your email to confirm. It deletes your space, your recordings, the files on your notes, your keys, your sign-ins and your connected AI apps, and ends your Google connection at Google. You can't undo it. Your notes stay on your phone.

## What is not kept

- The Relay Everything app has no ads and no analytics. It sends your notes, their files, health and places only to your Relay Everything server, and only with sending on. Your server sends them on only to your webhooks, and sends a file's name, type and size, never the file.
- To name a place, such as a street, the phone uses its own address lookup from Apple or Google, only with sending on. That lookup gets the place's coordinates, not the note. With sending off, a pinned note shows **Pinned**.
- The phone writes a voice note's words itself. No speech service on a network hears your voice.
- The speech model comes from [whisper.cpp's page on Hugging Face](https://huggingface.co/ggerganov/whisper.cpp), one time, after you tap **Get it**. Hugging Face sees the phone's internet address, the same as any download. It gets no note, no recording and no key.
- This website keeps no cookies and counts no visits. It is static pages, and it can't reach your server.

## Turn each part off

| Part | How |
|---|---|
| Everything sent | Turn off **Send to Relay Everything** in [Settings](../app/settings/). Health and location stop, and what of them did not go yet is deleted. |
| Voice notes | Do not tap **Get it**, or tap **Remove** in Settings to delete the speech model. Delete a recording by removing the app. |
| Pins on typed notes | Turn off **Pin notes to where I am** in Settings. |
| Location history | Turn off **Location history** in Settings. |
| Health | Turn off **Health** in Settings, and take back the permission in Apple Health or Health Connect. |
| One phone | Tap **Disconnect this phone** in Settings, or click **Turn off** beside it on your Relay Everything page: [Keys](../api/keys/#make-list-and-turn-off-keys). |
| Ring notes | Turn off the webhook in the Pebble app, or turn off the Pebble app's key on your Relay Everything page. |
| A webhook to your database | **Pause** or **Remove** it on the Relay Everything page: [Your own database](../connections/your-database/). |
| Google | Click **Disconnect** on the **Google** card: [Connect Google](../connections/google/#disconnect). |

Turning a part off stops new data. Data already in your space stays there until you [delete your account](#delete-your-account), and your notes stay on your phone.
