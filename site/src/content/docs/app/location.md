---
title: Location
description: Pin each note to a place, and keep a history of where you went.
---

Relay Everything uses your location two ways: it pins each typed note to where you are, and, with sending on, it keeps a history of where you went.

## Pin notes to where I am

**Pin notes to where I am** is off until you turn it on in [Settings](../settings/#notes). The app then asks for your location while you use it. Each typed note keeps where you were, with no signal too. With sending on, the phone names the place itself, such as a street. With sending off, it looks up no name, and the note shows **Pinned**.

## Location history

1. Open **Location**, under **On this phone** on Home.
2. If you are signed out, tap **Sign in**: [Connect a phone](../../start/connect-a-phone/). Location history works only once you sign in.
3. Turn on **Location history**.
4. Allow your location. An iPhone asks a second time: choose **Always Allow**, so the app can record when it is closed.

On Android, the app keeps a point each 100 m you move, not a constant fix, so it uses little battery. The notification *Relay Everything is keeping your places* stays while it records: Android asks for this.

On an iPhone, the phone keeps the points while the app is closed, and the app sends them when it next runs. Under **How often**, choose:

- **Save battery** (the default): a point at each move of about 500 m, and when you arrive at a place or leave it. It uses almost no battery.
- **Every 100 m**: a point each 100 m you move, or each 5 minutes while you stay. It uses more battery.

If you close the app with a swipe up, the iPhone stops keeping points until you open the app again.

The **Location** folder shows when the points last went, and how many wait, such as *Sent 14:05 · 12 points waiting*. Its row on Home shows the mode too, such as *Save battery · Sent 14:05*.

## Only to your own webhook

Signed in to Relay Everything, you can send your location history only to your own webhook and still sync your notes. On the Account page, under **Health, places, calendar and photos**, pick **Only my own webhook**. The phone then sends each point straight to your receiver as `location.points`, and Relay Everything gets none. The **Location** folder then says *Sent to your webhook* and the time. A note's pinned place is part of the note, so it still syncs with the note: turn off **Pin notes to where I am** to keep it off too. The points already sent stay on your page. [Settings](../settings/#health-places-calendar-and-photos-only-to-your-webhook)

## Turn it off

Turn off **Pin notes to where I am** in Settings, or **Location history** in the **Location** folder. The phone stops at once. Signing out also stops the history, and deletes the points that did not go yet. [Privacy](../../privacy/) says what the server keeps.
