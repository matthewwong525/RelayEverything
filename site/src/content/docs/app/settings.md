---
title: Settings
description: Each setting in the Relay Everything app, and what it does.
---

Open **Settings** with the round gear button at the top right of Home. Tap **Home** at the top left to go back. Each switch acts at once, and asks for its permission only when you turn it on. On a new phone, you are signed out and every switch is off: your notes stay on the phone, and the app sends nothing.

Settings starts with the [Account](#account) row, as the Apple Account row on an iPhone. Then it has three groups: **Appearance**, **Notes** and **Voice notes**. At the bottom, it shows the [version](#version) of the app. Each kind of phone data has its own folder on Home: [Health, Calendar, Location and Photos](#health-calendar-location-and-photos). The website's pages, linked below, give the details.

## Account

The first row of Settings shows your account:

| The row says | When |
|---|---|
| **Sign in to Relay Everything**, and *Your notes stay on this phone until you sign in.* | You are signed out. Nothing leaves this phone. |
| Your email and your server, such as `app.relayeverything.com` | The phone sends to your Relay Everything server. |
| **My own webhook**, and its address | The phone sends to [your own webhook](../../connections/your-database/#send-from-the-phone), with nothing on Relay Everything. |

Signed out, tap the row to open **Sign in**. **Sign in to connect** is first. Below it, **Scan a key**, **Use another server** and **Send to my own webhook instead** are the other ways. Signing in starts sending at once, after the app asks about your earlier notes. There is no separate switch. [Connect a phone](../../start/connect-a-phone/)

Signed in, tap the row to open the **Account** page:

| Row | What it does |
|---|---|
| Your email and server | The account this phone's key belongs to. |
| **AI apps** | The names of the AI apps you connected, such as *Claude*. Tap it to add or remove one on your Relay Everything page. [Connect your AI](../../connections/connect-your-ai/) |
| **Webhooks** | The names of the webhooks you added, such as *My database*. Tap it to add or remove one on your Relay Everything page. [Your own database](../../connections/your-database/) |
| **Open your Relay Everything page** | Opens `<your-relay-server>/apps/relay/` in the phone's browser, with your ring notes, their recordings, and the notes from all your devices. [Notes](../your-notes/#the-gear-and-your-relay-everything-page) |
| **Server** | The server this phone sends to. Change it to try a preview. [Connect a phone](../../start/connect-a-phone/#try-a-preview) |
| **Sign out** | In red. Asks first, then removes this phone's key and stops sending. Your notes from this phone stay here. Notes from your other devices leave this phone. You sign in again to send again. [Connect a phone](../../start/connect-a-phone/#sign-out) |

With your own webhook, the Account page shows its address with **Send a test**, the last answer that was not `2xx` or a file too large for your receiver, **Notes from elsewhere**, and **Stop sending** in red. **Stop sending** asks first. It keeps the webhook's address and secret on the phone, so you can send there again with no new secret.

Signing out or stopping stops health, the calendar, location history and photos, and deletes what of them did not go yet.

## Appearance

Pick how the app looks:

| Choice | What it does |
|---|---|
| **System** | Follows the phone: light in light mode, dark in dark mode. The app starts on **System**. |
| **Light** | Keeps the app light, also when the phone is in dark mode. |
| **Dark** | Keeps the app dark, also when the phone is in light mode. |

The phone remembers your choice. The share card from other apps follows the phone's own setting.

## Notes

| Setting | What it does |
|---|---|
| **Pin notes to where I am** | Each typed note keeps where you were. It works with no signal. [Location](../location/#pin-notes-to-where-i-am) |

## Voice notes

This group shows if the speech model is on this phone, and its size. Your voice is written into words on this phone, and recordings never leave it. Tap **Remove** to delete the model and free 57 MB. The voice notes you made stay, with their words and recordings. The next voice note asks to get the model again. [Voice notes](../voice-notes/#get-the-speech-model)

## Version

The last line of Settings gives the app's version and build number, such as *Relay Everything 1.4.0 (91)*. Use it to know which TestFlight build you have.

## Health, Calendar, Location and Photos

Each has its own folder under **On this phone** on Home. Its row on Home says *Off*, or when the data last went and how many wait.

| Folder | What it holds |
|---|---|
| **Location** | **Location history**: keeps a point each 100 m you move, so you can see where you went. On an iPhone, **How often** holds **Save battery** and **Every 100 m**. [Location](../location/#location-history) |
| **Health** | **Health**: sends steps, heart rate, sleep, workouts, weight, blood pressure and more every hour, and the last 90 days the first time. [Health](../health/) |
| **Calendar** | **Calendar**: sends the events of your phone's calendars, the last 90 days and the next 90 days, then each change. Under **Calendars**, a switch for each calendar turns that one off. [Calendar](../calendar/) |
| **Photos** | **Photos**: sends the new photos you take, with when and where you took them, to the place sending goes: your server, so your AI can see them, or your own webhook. **Send photos on mobile data** is off at first: photos wait for Wi-Fi. Its row on Home says *Off*, *On · Wi-Fi only* or *On · Wi-Fi and mobile data*. [Photos](../photos/) |

Each works only once you sign in. Signed out, its switch is dim, and the page says, for example, *Health works once you sign in. Nothing leaves this phone until you do.* Tap **Sign in** to open the same sign-in as the [Account](#account) row. Once you sign in, the Location, Health and Calendar switches say when they last sent, and how many wait.

The key, and your webhook's address and secret, stay in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Settings on your Relay Everything page

Your account's own settings are on your Relay Everything page, not in the app: the app only shows their names. Sign in there first: [Sign up](../../start/sign-up/).

| Setting | What it does |
|---|---|
| **Add a device** | Makes a key for a phone, a Claude Code computer or a script, and shows it once: as a QR code for a phone. [Connect a phone](../../start/connect-a-phone/#make-a-key-with-a-qr-code) |
| **Delete all photos** | Deletes every photo your phones sent. Your notes, recordings, health and places stay. You can't undo it. [Photos](../photos/#delete-all-photos) |
| The list of devices, with **Turn off** | Shows each device's key. **Turn off** stops that key at once, and the others go on. [Keys](../../api/keys/#make-list-and-turn-off-keys) |
| **Delete my account** | Deletes your space, recordings, photos, keys, sign-ins and connected AI apps, after you type your email. You can't undo it. [Privacy](../../privacy/#delete-your-account) |
