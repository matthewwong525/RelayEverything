---
title: Connect a phone
description: Turn on sending, and sign in from the app to give the phone its own key, so it can send notes to your account.
---

The Relay Everything app keeps your notes on the phone, with no key. To send them to your Relay Everything account, you turn on sending and connect the phone with its own key. The easy way is to sign in from the app. You need an account first: [Sign up](../sign-up/).

To send straight to your own database, with no account and nothing on Relay Everything, pick **My own webhook** instead: [Send from the phone](../../connections/your-database/#send-from-the-phone).

## Connect by signing in

1. Open the Relay Everything app. On Home, under **Connections**, tap **Sending**.
2. Turn on **Send my notes**. The app shows **Where should the phone send?**, with **Relay Everything** picked.
3. Tap **Sign in to connect**. A sign-in page opens in the app. Sign in, if you are not signed in on the phone already.
4. The page asks **Connect this phone?**, with a name for the phone. Change the name if you want, and tap **Connect**.
5. The app comes back with its own key, and checks it with the server. If you wrote notes before, the app asks **Send your earlier notes too?**: see step 4 of [Connect with a QR code](#connect-with-a-qr-code).

The key never shows. It goes from the server to the phone only, and works only with a secret that the phone made for this one sign-in. Tap **Cancel** on the page, or close it, and the phone gets no key.

On your own server, tap **Use another server**, and enter its address, such as `https://<your-relay-server>`.

## Make a key with a QR code

To connect with no sign-in on the phone, make the key on your Relay Everything page.

1. Open `https://<your-relay-server>/apps/relay/` on a computer or another phone, and sign in.
2. Click **Add a device**, and give it a name, such as `Android phone`.
3. The page shows the key once, as a QR code. Keep the page open while you connect.

The key starts with `rek_`. It adds data only to your own space. [Keys](../../api/keys/) tells more about keys.

## Connect with a QR code

1. Open the Relay Everything app. On Home, under **Connections**, tap **Sending**.
2. Turn on **Send my notes**. The app shows **Where should the phone send?**, with **Relay Everything** picked.
3. Under **Or**, below **Use a key from Add a device on your Relay Everything page**, tap **Scan the QR code**, and point the camera at the key's QR code. The key holds the server's address, so you type no address.
   Or tap **Or paste the key**, paste it, and tap **Connect**.
4. If you wrote notes before, the app asks **Send your earlier notes too?** Tap **Send them** to send them, or **Only new notes** to keep them only on the phone. The app asks again each time you turn sending on.

To connect, the phone checks its key with the server, and reads no data. Once connected, it reads the names of your AI apps and webhooks, for **Connections** on Home: [Connections on Home](../../app/your-notes/#connections-on-home). Then your notes go to your space, and the phone gets your notes from your other phones, email and AI apps: [Your notes on every phone](../../app/your-notes/#your-notes-on-every-phone). The key reads no health, calendar, places or photos. Close the page with the QR code when the phone is connected: the key does not show again.

## Stop sending

Turn off **Send my notes** on the **Sending** page, and tap **Stop sending**. New notes stay on the phone. Notes already on your server stay there. Health, location and photos stop, and what of them did not go yet is deleted. The key stays on the phone, so you can turn sending on again with no new key: tap **Send to Relay Everything** on **Where should the phone send?**.

## Turn a phone off

- **On the phone:** open **Sending** on Home, then tap **Disconnect this phone**. The key leaves the phone, and sending turns off. Your notes stay on the phone. You need a new key to send again.
- **From the Relay Everything page:** find the phone in your list of devices, and click **Turn off**. That key stops at once, and the other keys go on.

## Try a preview

A preview of a change to Relay Everything's own server has its own address, its own accounts and its own keys. In the app, tap **Use another server**, enter the preview's address, and sign in there. Or make a key there with **Add a device**, connect with it, then open **Sending**, tap **Server**, and enter the preview's address.

## Next

[Your notes](../../app/your-notes/) shows what you can do with each note.
