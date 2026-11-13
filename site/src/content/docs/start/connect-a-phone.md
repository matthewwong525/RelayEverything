---
title: Connect a phone
description: Sign in from the app's Settings to give the phone its own key, so it sends notes to your account.
---

The Relay Everything app keeps your notes on the phone, with no key. To send them to your Relay Everything account, you sign in, and the phone gets its own key. Signing in starts sending in the same step. You need an account first: [Sign up](../sign-up/).

To send straight to your own database, with no account and nothing on Relay Everything, tap **Don't want an account? Use your own webhook** on the **Sign in** screen: [Send from the phone](../../connections/your-database/#send-from-the-phone).

## Connect by signing in

1. Open the Relay Everything app. Tap the round gear at the top right of Home to open **Settings**.
2. Tap **Sign in to Relay Everything**, the account card at the top. The app shows **Sign in**.
3. Tap **Sign in**. A sign-in page opens in the app. Sign in, if you are not signed in on the phone already.
4. The page asks **Connect this phone?**, with a name for the phone. Change the name if you want, and tap **Connect**.
5. The app comes back with its own key, and checks it with the server. If you wrote notes before, the app asks **Send your earlier notes too?** Tap **Send them** to send them, or **Only new notes** to keep them only on the phone. The app asks again each time you sign in.
6. The phone sends, and the account card shows your email and *Signed in*.

The key never shows. It goes from the server to the phone only, and works only with a secret that the phone made for this one sign-in. Tap **Cancel** on the page, or close it, and the phone gets no key. Each phone gets its key only this way: your Relay Everything page makes no phone key and no QR code.

The app signs in only to Relay Everything. A phone that already sends to another server, such as [your own server](../run-your-own/), keeps sending there. On your own server, use your Relay Everything page in a browser and [Relay Everything in Claude Code and Codex](../../connections/claude-code/).

To connect, the phone checks its key with the server, and reads no data. Once connected, it reads your account's email, the names of your phones, computers, AI apps and webhooks, and your two notes addresses, for the **Account** page, **Connect your AI** and **Email notes**: [Account](../../app/settings/#account). Then your notes go to your space, and the phone gets your notes from your other phones, email and AI apps: [Your notes on every phone](../../app/your-notes/#your-notes-on-every-phone). The key reads no health, calendar, places or photos.

## Sign out

1. In **Settings**, tap the account card, with your email, to open the **Account** page.
2. Tap **Sign out** beside your email, and tap **Sign out** again to confirm.

The key leaves the phone, and sending stops. Health, location and photos stop, and what of them did not go yet is deleted. Your notes from this phone stay on it, and notes already on your server stay there. Notes from your other devices leave this phone. To send again, sign in again: the phone gets a new key.

With your own webhook, the **Account** page has **Stop sending** in place of **Sign out**. The phone keeps the webhook's address and secret, so you can send there again with no new secret.

## Sign out a lost phone

Sign out a lost or sold phone from another phone or from a computer:

- **On another phone:** in **Settings**, tap the account card. Under **Phones**, tap **Sign out** beside the lost phone, and confirm.
- **From the Relay Everything page:** open **Settings**, then **Account**. Under **Phones**, click **Sign out** beside the lost phone, and confirm.

That phone's key stops at its next request, and your other phones and computers go on.

## Try a preview

A preview of a change to Relay Everything's own server has its own address, its own accounts and its own keys. The app signs in only to Relay Everything, so try a preview in a browser: open its address, and sign in there.

## Next

[Your notes](../../app/your-notes/) shows what you can do with each note.
