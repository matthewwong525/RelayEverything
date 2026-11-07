---
title: Settings
description: Each setting in the Relay Everything app, and what it does.
---

Open **Settings** from the gear at the top of your notes. Each switch acts at once, and asks for its permission only when you turn it on. On a new phone, every switch is off: your notes stay on the phone, and the app sends nothing.

| Setting | What it does |
|---|---|
| **Pin notes to where I am** | Each typed note keeps where you were. It works with no signal. [Location](../location/#pin-notes-to-where-i-am) |
| **Voice notes** | Shows the speech model and its size, with **Remove**. Your voice is written into words on this phone, and recordings never leave it. [More below](#voice-notes) |
| **Send to Relay Everything** | Sends your notes to your space on your Relay Everything server, which can pass them to your own database and your AI. Off: nothing leaves this phone. Ring notes from the Pebble app come through your server, so they need it on. [Connect a phone](../../start/connect-a-phone/) |
| **Health: steps, heart rate, sleep, workouts** | Sends them every hour. Only with sending on. [Health](../health/) |
| **Location history** | Keeps a point each 100 m you move, so ring notes get a place too. Only with sending on. [Location](../location/#location-history) |
| **Photos** | Sends the new photos you take, with when and where you took them, so your AI can see them. Only with sending on. [Photos](../photos/) |
| **Send photos on mobile data** | Off: photos wait for Wi-Fi. Only with **Photos** on. [Photos](../photos/#wi-fi-or-mobile-data) |
| **Server** | The server this phone sends to. Change it to try a preview. Shows when a key is kept. [Connect a phone](../../start/connect-a-phone/#try-a-preview) |
| **Disconnect this phone** | Removes the key from this phone and turns sending off. Your notes stay here. You need a new key to send again. Shows when a key is kept. |

Turning sending off asks first, then stops health, location history and photos, and deletes what of them did not go yet. Your notes, and the key, stay on the phone. [Connect a phone](../../start/connect-a-phone/#stop-sending)

## Voice notes

The **Voice notes** part of Settings shows if the speech model is on this phone, and its size. Tap **Remove** to delete it and free 57 MB. The voice notes you made stay, with their words and recordings. The next voice note asks to get the model again. [Voice notes](../voice-notes/#get-the-speech-model)

The key stays in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Settings on your Relay Everything page

Your account's own settings are on your Relay Everything page, not in the app. Sign in there first: [Sign up](../../start/sign-up/).

| Setting | What it does |
|---|---|
| **Add a device** | Makes a key for a phone, the Pebble app or a Claude Code computer, and shows it once as a QR code. [Connect a phone](../../start/connect-a-phone/#make-the-key) |
| **Delete all photos** | Deletes every photo your phones sent. Your notes, recordings, health and places stay. You can't undo it. [Photos](../photos/#delete-all-photos) |
| The list of devices, with **Turn off** | Shows each device's key. **Turn off** stops that key at once, and the others go on. [Keys](../../api/keys/#make-list-and-turn-off-keys) |
| **Delete my account** | Deletes your space, recordings, photos, keys, sign-ins and connected AI apps, after you type your email. You can't undo it. [Privacy](../../privacy/#delete-your-account) |
