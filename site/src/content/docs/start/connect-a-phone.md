---
title: Connect a phone
description: Sign in from the app's Settings to give the phone its own key, so it sends notes to your account.
---

The Relay Everything app keeps your notes on the phone, with no key. To send them to your Relay Everything account, you sign in, and the phone gets its own key. Signing in starts sending in the same step. You need an account first: [Sign up](../sign-up/).

To send straight to your own database, with no account and nothing on Relay Everything, tap **Send to my own webhook instead** on the **Sign in** screen: [Send from the phone](../../connections/your-database/#send-from-the-phone).

## Connect by signing in

1. Open the Relay Everything app. Tap the round gear at the top right of Home to open **Settings**.
2. Tap **Sign in to Relay Everything**, the first row. The app shows **Sign in**.
3. Tap **Sign in to connect**. A sign-in page opens in the app. Sign in, if you are not signed in on the phone already.
4. The page asks **Connect this phone?**, with a name for the phone. Change the name if you want, and tap **Connect**.
5. The app comes back with its own key, and checks it with the server. If you wrote notes before, the app asks **Send your earlier notes too?**: see step 4 of [Connect with a QR code](#connect-with-a-qr-code). Then the phone sends, and the first row of Settings shows your email and your server.

The key never shows. It goes from the server to the phone only, and works only with a secret that the phone made for this one sign-in. Tap **Cancel** on the page, or close it, and the phone gets no key.

On your own server, tap **Use another server**, and enter its address, such as `https://<your-relay-server>`.

## Make a key with a QR code

To connect with no sign-in on the phone, make the key on your Relay Everything page.

1. Open `https://<your-relay-server>/apps/relay/` on a computer or another phone, and sign in.
2. Open **Settings**, then **Devices**. Click **Add a device**, and give it a name, such as `Android phone`.
3. The page shows the key once, as a QR code. Keep the page open while you connect.

The key starts with `rek_`. It adds data only to your own space. [Keys](../../api/keys/) tells more about keys.

## Connect with a QR code

1. Open the Relay Everything app. Tap the round gear at the top right of Home to open **Settings**.
2. Tap **Sign in to Relay Everything**, the first row. The app shows **Sign in**.
3. Tap **Scan a key**, and point the camera at the key's QR code. The key holds the server's address, so you type no address.
   On the same phone, copy the key, paste it in **Or paste the key**, and tap **Connect**.
4. If you wrote notes before, the app asks **Send your earlier notes too?** Tap **Send them** to send them, or **Only new notes** to keep them only on the phone. The app asks again each time you sign in.

To connect, the phone checks its key with the server, and reads no data. Once connected, it reads your account's email and the names of your AI apps and webhooks, for the **Account** page in Settings: [Account](../../app/settings/#account). Then your notes go to your space, and the phone gets your notes from your other phones, email and AI apps: [Your notes on every phone](../../app/your-notes/#your-notes-on-every-phone). The key reads no health, calendar, places or photos. Close the page with the QR code when the phone is connected: the key does not show again.

## Sign out

1. In **Settings**, tap the first row, with your email, to open the **Account** page.
2. Tap **Sign out**, in red, and tap **Sign out** again to confirm.

The key leaves the phone, and sending stops. Health, location and photos stop, and what of them did not go yet is deleted. Your notes from this phone stay on it, and notes already on your server stay there. Notes from your other devices leave this phone. To send again, sign in again: the phone gets a new key.

With your own webhook, the **Account** page has **Stop sending** in place of **Sign out**. The phone keeps the webhook's address and secret, so you can send there again with no new secret.

## Turn a phone off

- **On the phone:** [sign out](#sign-out).
- **From the Relay Everything page:** open **Settings**, then **Devices**. Find the phone, and click **Turn off**. That key stops at once, and the other keys go on.

## Try a preview

A preview of a change to Relay Everything's own server has its own address, its own accounts and its own keys. In the app, tap **Use another server**, enter the preview's address, and sign in there. Or make a key there with **Add a device**, connect with it, then open the **Account** page in Settings, tap **Server**, and enter the preview's address.

## Next

[Your notes](../../app/your-notes/) shows what you can do with each note.
