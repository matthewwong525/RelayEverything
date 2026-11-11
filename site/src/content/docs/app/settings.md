---
title: Settings
description: Each setting in the Relay Everything app, and what it does.
---

Open **Settings** with the round gear button at the top right of Home. Tap **Home** at the top left to go back. Each switch acts at once, and asks for its permission only when you turn it on. On a new phone, you are signed out and every switch is off: your notes stay on the phone, and the app sends nothing.

Settings starts with the [Account](#account) card, as the Apple Account row on an iPhone. Then it has two groups: **Appearance** and **Voice notes**. At the bottom, it shows the [version](#version) of the app. Settings on your Relay Everything page has the same account card and **Appearance**: [Settings on your Relay Everything page](#settings-on-your-relay-everything-page). Each kind of phone data has its own folder on Home: [Health, Calendar, Location and Photos](#health-calendar-location-and-photos). The website's pages, linked below, give the details.

## Account

The first row of Settings is your account card:

| The card says | When |
|---|---|
| **Sign in to Relay Everything**, and *Your notes stay on this phone until you sign in.* | You are signed out. Nothing leaves this phone. |
| Your email, and *Signed in* | The phone sends to Relay Everything. |
| **My own webhook**, and the webhook's host | The phone sends to [your own webhook](../../connections/your-database/#send-from-the-phone), with no account and nothing on Relay Everything. |

Signed out, tap the card to open **Sign in**. It has one button, **Sign in**, and one link, **Don't want an account? Use your own webhook**. Signing in starts sending at once, after the app asks about your earlier notes. There is no separate switch. The app signs in only to Relay Everything. A phone that already sends to another server keeps sending there. [Connect a phone](../../start/connect-a-phone/)

Once you are signed in, notes send by themselves, also when the phone gets a connection again after it had none. There is no **Sync now** or **Send now**: pull your notes down to sync now. [The sync state](../your-notes/#the-sync-state)

Signed in, tap the card to open the **Account** page:

| Part | What it does |
|---|---|
| Your email, *Signed in*, and **Sign out** | The account this phone's key belongs to. **Sign out** asks first, then removes this phone's key and stops sending. Your notes from this phone stay here. Notes from your other devices leave this phone. You sign in again to send again. [Connect a phone](../../start/connect-a-phone/#sign-out) |
| **Phones** | Each of your phones by name. This one is marked *This phone*. Each other phone has **Sign out**, which asks first, then stops that phone at its next request. The other phones and your computers go on. Use it for a lost or sold phone. |
| **Advanced** | **Webhooks**: *Send a copy to your own server*. You do not need it to use Relay Everything. [Webhooks](#webhooks) |
| **Delete my account** | Last, in red. Opens your Relay Everything page, where you delete your account. [Delete your account](../../start/sign-up/#delete-your-account) |

With your own webhook and no account, the card opens an **Account** page with the webhook's address and **Send a test**, the last answer that was not `2xx` or a file too large for your receiver, **Sign in to Relay Everything**, and **Stop sending** in red. **Stop sending** asks first. It keeps the webhook's address and secret on the phone, so you can send there again with no new secret.

### Sign in and keep your webhook

On the webhook Account page, tap **Sign in to Relay Everything** to sync your notes with your page, your AI and your other phones. It opens the same **Sign in** as the account card, with no **Don't want an account? Use your own webhook**. After you sign in:

- Your notes go to Relay Everything. Health, places, calendar and photos still go only to your webhook, as with [**Only to my own webhook**](#health-places-calendar-and-photos-only-to-your-webhook). **Webhooks** on the Account page shows that switch on.
- If notes already went to your webhook, the app asks *Send your 12 earlier notes too?*: *They are not on Relay Everything yet.* **Send them** puts them on your page, oldest first, with their files. **Only new notes** leaves them only at your webhook.
- Your webhook gets no more notes from the phone. To get your notes there too, add it under **Webhooks** on your Relay Everything page, and the server sends them on. A short message at the bottom of the screen says so. [Your own database](../../connections/your-database/)

Go back from **Sign in**, or close the sign-in, to change nothing: the phone still sends everything to your webhook.

Signing out or stopping stops health, the calendar, location history and photos, and deletes what of them did not go yet.

### Webhooks

On the **Account** page, under **Advanced**, tap **Webhooks**. It is for developers: you do not need it to use Relay Everything. It shows:

- The names of the webhooks you added, such as *My database*.
- **Add or change on your Relay Everything page**, which opens **Webhooks** there. [Your own database](../../connections/your-database/)
- Signed in, the switch **Only to my own webhook**, for health, places, calendar and photos. It is off at first. [Below](#health-places-calendar-and-photos-only-to-your-webhook)

Everything else goes to Relay Everything.

### Health, places, calendar and photos only to your webhook

Signed in, you can keep your personal data off Relay Everything and still sync your notes. On the **Account** page, under **Advanced**, open **Webhooks** and turn on **Only to my own webhook**:

- The phone sends health samples, location points, calendar events and new photos straight to [your own webhook](../../connections/your-database/#send-from-the-phone). Relay Everything never gets them.
- Your notes and their files still sync through Relay Everything. A note keeps no place: where you made it is a location point, and goes to your webhook.
- With no webhook on the phone, the switch first opens the webhook's setup: [the four steps](../../connections/your-database/#send-from-the-phone). Go back to change nothing. A webhook you added on your Relay Everything page does not count, because the server never gives its secret to a phone.
- **Webhooks** then shows the webhook's address, **Send a test**, and its last failure, if any.
- What already went to Relay Everything stays in your space. To delete it, [delete your account](../../start/sign-up/#delete-your-account), or [delete all photos](../photos/#delete-all-photos).

A phone that sends everything to your webhook gets here in one step: [sign in and keep your webhook](#sign-in-and-keep-your-webhook).

What you give up: your AI apps show none of your health, places, calendar or photos from then on. Nothing retries for you on a server: when the phone is off or offline, the data waits for the phone's next round. A receiver that is down holds back only this data; your notes still sync, and the other way round.

If the phone loses the webhook, such as after a restore, the data waits on the phone and never goes to Relay Everything. **Webhooks** shows **Set your webhook again**. Turn off **Only to my own webhook** to send them to Relay Everything again, with what waits; the calendar sends its whole window. **Sign out** keeps your choice and the webhook.

## Appearance

Pick how the app looks:

| Choice | What it does |
|---|---|
| **System** | Follows the phone: light in light mode, dark in dark mode. The app starts on **System**. |
| **Light** | Keeps the app light, also when the phone is in dark mode. |
| **Dark** | Keeps the app dark, also when the phone is in light mode. |

The phone remembers your choice. The share card from other apps follows the phone's own setting.

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
| **Photos** | **Photos**: sends the new photos you take, with when and where you took them, to where your health and places go: your server, so your AI can see them, or your own webhook. **Send photos on mobile data** is off at first: photos wait for Wi-Fi. Its row on Home says *Off*, *On · Wi-Fi only* or *On · Wi-Fi and mobile data*. [Photos](../photos/) |

Each works only once you sign in. Signed out, its switch is dim, and the page says, for example, *Health works once you sign in. Nothing leaves this phone until you do.* Tap **Sign in** to open the same sign-in as the [account card](#account). Once you sign in, the Location, Health and Calendar switches say when they last sent, and how many wait. With **Only to my own webhook**, they say *Sent to your webhook* and the time. When you change where they go, they say *Not sent yet* until the new place gets data.

The key, and your webhook's address and secret, stay in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Settings on your Relay Everything page

Your account's own settings are on your Relay Everything page too. Sign in there, then click **Settings** at the bottom of the left bar. It lists only **Account** and **Appearance**. **Account** has the same parts as on the phone, and its **Advanced** part also has **API keys**, for your own scripts. On the web, **Webhooks** adds, changes and removes your webhooks. **Connect your AI** and **Email notes** are in the left bar, under **Other connections**. [On a computer](../on-a-computer/#settings) says what each part does.
