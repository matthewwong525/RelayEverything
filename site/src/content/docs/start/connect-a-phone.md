---
title: Connect a phone
description: Turn on sending, and give a phone its own key from your Relay Everything page, so it can send notes to your account.
---

The Relay Everything app keeps your notes on the phone, with no key. To send them to your Relay Everything account, you turn on sending and connect the phone with its own key. The key also holds the server's address, so you type no address.

## Make the key

You make one key for each phone, on your Relay Everything page. You need an account first: [Sign up](../sign-up/).

1. Open `https://<your-relay-server>/apps/relay/` on a computer or another phone, and sign in.
2. Click **Add a device**, and give it a name, such as `Android phone`.
3. The page shows the key once, as a QR code. Keep the page open while you connect.

The key starts with `rek_`. It adds data only to your own space. [Keys](../../api/keys/) tells more about keys.

## Connect

1. Open the Relay Everything app, then open **Settings** from the gear at the top.
2. Turn on **Send to Relay Everything**. The app shows **Connect Relay Everything**.
3. Tap **Scan the QR code**, and point the camera at the key's QR code.
   Or tap **Or paste the key**, paste it, and tap **Connect**.
4. If you wrote notes before, the app asks **Send your earlier notes too?** Tap **Send them** to send them, or **Only new notes** to keep them only on the phone. The app asks again each time you turn sending on.

To connect, the phone checks its key with the server, and reads no data. Then your notes go to your space. The key only adds data, so the phone shows only its own notes: ring notes and recordings are on your Relay Everything page, and **Open your Relay Everything page** opens it. Close the page with the QR code when the phone is connected: the key does not show again.

## Stop sending

Turn off **Send to Relay Everything** in **Settings**, and tap **Stop sending**. New notes stay on the phone. Notes already on your server stay there. Health and location stop, and what of them did not go yet is deleted. The key stays on the phone, so you can turn sending on again with no new key.

## Turn a phone off

- **On the phone:** open **Settings**, then tap **Disconnect this phone**. The key leaves the phone, and sending turns off. Your notes stay on the phone. You need a new key to send again.
- **From the Relay Everything page:** find the phone in your list of devices, and click **Turn off**. That key stops at once, and the other keys go on.

## Try a preview

A preview of a change to Relay Everything's own server has its own address, its own accounts and its own keys. Sign in on the preview's page, make a key there with **Add a device**, then in the app open **Settings**, tap **Server**, and enter the preview's address.

## Next

[Set up the Pebble webhook](../pebble-webhook/), so the ring's notes reach Relay Everything.
