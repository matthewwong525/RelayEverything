---
title: Settings
description: Each setting in the Relay Everything app, and what it does.
---

Open **Settings** from the gear at the top of your notes. Each switch acts at once, and asks for its permission only when you turn it on. On a new phone, every switch is off: your notes stay on the phone, and the app sends nothing.

| Setting | What it does |
|---|---|
| **Pin notes to where I am** | Each typed note keeps where you were. It works with no signal. [Location](../location/#pin-notes-to-where-i-am) |
| **Voice notes** | Shows the speech model and its size, with **Remove**. Your voice is written into words on this phone, and recordings never leave it. [More below](#voice-notes) |
| **Send my notes** | Sends your notes to one place: your space on your Relay Everything server, which can pass them to your own database and your AI, or [your own webhook](../../connections/your-database/#send-from-the-phone), with nothing on Relay Everything. Turning it on asks which place. The line under it names the place. Off: nothing leaves this phone. [Connect a phone](../../start/connect-a-phone/) |
| **Health: steps, heart rate, sleep and more** | Sends steps, heart rate, sleep, workouts, weight, blood pressure and more every hour, and the last 90 days the first time. Only with sending on. [Health](../health/) |
| **Calendar** | Sends the events of your phone's calendars: the last 90 days and the next 90 days, then each change. Under it, a switch for each calendar turns that one off. Only with sending on. [Calendar](../calendar/) |
| **Location history** | Keeps a point each 100 m you move, so you can see where you went. Only with sending on. [Location](../location/#location-history) |
| **Photos** | Sends the new photos you take, with when and where you took them, to the place sending goes: your server, so your AI can see them, or your own webhook. Only with sending on. [Photos](../photos/) |
| **Send photos on mobile data** | Off: photos wait for Wi-Fi. Only with **Photos** on. [Photos](../photos/#wi-fi-or-mobile-data) |
| **Where the phone sends** | Moves sending to the other place. What waits to send goes to the new place. Shows while sending is on. |
| **Webhook** | Your webhook's address, with **Send a test**. Under it, the last answer that was not `2xx`, or a file too large for your receiver. Shows while the phone sends to your webhook. [Your own database](../../connections/your-database/#send-from-the-phone) |
| **Server** | The server this phone sends to. Change it to try a preview. Shows when a key is kept and the phone sends to your server. [Connect a phone](../../start/connect-a-phone/#try-a-preview) |
| **Disconnect this phone** | Removes the key from this phone and turns sending off. Your notes stay here. You need a new key to send again. Shows when a key is kept and the phone sends to your server. |

Turning sending off asks first, then stops health, the calendar, location history and photos, and deletes what of them did not go yet. Your notes, the key and the webhook stay on the phone. [Connect a phone](../../start/connect-a-phone/#stop-sending)

## Voice notes

The **Voice notes** part of Settings shows if the speech model is on this phone, and its size. Tap **Remove** to delete it and free 57 MB. The voice notes you made stay, with their words and recordings. The next voice note asks to get the model again. [Voice notes](../voice-notes/#get-the-speech-model)

The key, and your webhook's address and secret, stay in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Settings on your Relay Everything page

Your account's own settings are on your Relay Everything page, not in the app. Sign in there first: [Sign up](../../start/sign-up/).

| Setting | What it does |
|---|---|
| **Add a device** | Makes a key for a phone, a Claude Code computer or a script, and shows it once: as a QR code for a phone. [Connect a phone](../../start/connect-a-phone/#make-a-key-with-a-qr-code) |
| **Delete all photos** | Deletes every photo your phones sent. Your notes, recordings, health and places stay. You can't undo it. [Photos](../photos/#delete-all-photos) |
| The list of devices, with **Turn off** | Shows each device's key. **Turn off** stops that key at once, and the others go on. [Keys](../../api/keys/#make-list-and-turn-off-keys) |
| **Delete my account** | Deletes your space, recordings, photos, keys, sign-ins and connected AI apps, after you type your email. You can't undo it. [Privacy](../../privacy/#delete-your-account) |
