---
title: Location
description: Pin each note to a place, and keep a history of where you went, as stays and trips.
---

Relay Everything uses your location two ways: it pins each typed note to where you are, and, with sending on, it keeps a history of where you went, as stays at named places and trips between them.

## Pin notes to where I am

**Pin notes to where I am** is off until you turn it on in [Settings](../settings/#notes). The app then asks for your location while you use it. Each typed note keeps where you were, with no signal too. With sending on, the phone names the place itself, such as a street. With sending off, it looks up no name, and the note shows **Pinned**.

## Location history

1. Open **Location**, under **On this phone** on Home.
2. If you are signed out, tap **Sign in**: [Connect a phone](../../start/connect-a-phone/). Location history works only once you sign in.
3. Turn on **Location history**.
4. Allow your location. An iPhone asks a second time: choose **Always Allow**, so the app can record when it is closed.
5. Allow motion: **Motion & Fitness** on an iPhone, **Physical activity** on Android. The phone uses it to tell a walk from a drive. If you say no, the phone guesses from your speed. The phone does not ask again: change it in the phone's settings.

On Android, the app keeps a point each 100 m you move, not a constant fix, so it uses little battery. The notification *Relay Everything is keeping your places* stays while it records: Android asks for this.

On an iPhone, the phone keeps the points while the app is closed, and the app sends them when it next runs. Under **How often**, choose:

- **Save battery** (the default): a point at each move of about 500 m, and when you arrive at a place or leave it. It uses almost no battery.
- **Every 100 m**: a point each 100 m you move, or each 5 minutes while you stay. It uses more battery.

If you close the app with a swipe up, the iPhone stops keeping points until you open the app again.

## Stays and trips

The phone turns your points into stays and trips itself, the same as Google Maps Timeline. It does this from the update that added stays: days you sent before keep their list of streets.

- **A stay** is a time you were in one spot, inside about 100 m, for 5 minutes or more. A night at home with no new point is one stay. Two stays at the same spot less than 15 minutes apart are one stay.
- **A trip** is the time between two stays. A drive is one trip, not one row for each street.

The phone keeps only the stay or trip you are in now. When it ends, the phone sends it, with its points unless you picked **Only stays and trips** under [What to send](#what-to-send), and keeps none of them. The stay you are in now goes when it reaches 5 minutes, again as it grows, and again when you leave. If you turn off **Location history**, or pick **Only points**, the stay you are in goes as ended, at the last time the phone knew you were there. Days and times with points but no stays, such as with **Only points**, show your streets, as before.

Each trip tells how you went, how far, and how long. The distance adds each step between the points, so it is never longer than the real trip.

| The phone knows | Mode |
|---|---|
| Motion: walking, running, cycling, in a vehicle | Walking, running, cycling, driving |
| No motion, speed under 8 km/h | Walking |
| No motion, 8 to 25 km/h | Cycling |
| No motion, 25 to 250 km/h | Driving |
| Over 250 km/h | Flying |
| Over 60 minutes with no point on the way | Unknown |

### How a stay gets its name

The phone names each stay one time, with sending on. It uses the first of these that it finds:

1. **Your calendar**, with **Calendar** on: an event at that time, with a place within 150 m of the stay, such as *Smile Dental*. An online meeting does not change the name of the place where you are.
2. **Apple Maps**, on an iPhone only: the nearest place within 50 m, such as *Corner Café*. The phone asks only when it knows where it is to within 50 m, so a stop on a road never gets the name of a shop.
3. **The street**, from the phone's address lookup.
4. **The coordinates**, such as *43.651, -79.383*.

A stay named from your calendar or Apple Maps also has its street. Android has no shop names: its free lookup gives streets only.

## What to send

Under **What to send** in the **Location** folder, choose:

- **Stays, trips and points** (the default): where you stayed, how you moved, and each point on the way.
- **Only stays and trips**: where you stayed and how you moved. No point on the way leaves the phone. The phone uses the points to find the stays and trips, then deletes them. When you pick it, the points that wait on the phone are deleted.
- **Only points**: each point, with its street, as before. The phone makes no stay or trip, and asks for no motion.

Your choice applies on both phones, to your Relay Everything server and to [your own webhook](../../connections/your-database/#send-from-the-phone). Stays and trips go to the same place as the points: your server, and from there to each webhook you tick for **Location history**.

## When it last sent

The **Location** folder shows when the points last went, and how many wait, such as *Sent 14:05 · 12 points waiting*. Its row on Home shows the mode too, such as *Save battery · Sent 14:05*.

## Only to your own webhook

Signed in to Relay Everything, you can send your location history only to your own webhook and still sync your notes. On the Account page, under **Health, places, calendar and photos**, pick **Only my own webhook**. The phone then sends each point straight to your receiver as `location.points`, and each stay and trip as `location.stays`, and Relay Everything gets none of them. The **Location** folder then says *Sent to your webhook* and the time. A note's pinned place is part of the note, so it still syncs with the note: turn off **Pin notes to where I am** to keep it off too. The points already sent stay in your space. [Settings](../settings/#health-places-calendar-and-photos-only-to-your-webhook)

## Turn it off

Turn off **Pin notes to where I am** in Settings, or **Location history** in the **Location** folder. The phone stops at once. Signing out also stops the history, and deletes the points, stays and trips that did not go yet. [Privacy](../../privacy/) says what the server keeps.
