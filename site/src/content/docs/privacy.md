---
title: Privacy
description: What Relay keeps, where it keeps it, and how to turn each part off.
---

Relay keeps your notes on your phone. When you turn on sending, it keeps your notes, health and places on your own Relay server, and nowhere else. This website holds none of them.

## What is kept, and where

| What | Where | Sent when |
|---|---|---|
| Typed notes, with their pin | The phone's own storage, always | Never, while sending is off |
| Typed notes, with their place | Your Relay server's database | With sending on: each time you save a note. Notes from before go only if you tap **Send them**. |
| Ring notes: the words and the recording | Your Relay server: the words in its database, the recording in its file store | Each time you hold the ring and talk, through the Pebble app |
| Steps, heart rate, sleep and workouts | Your Relay server's database | On open and every hour, with sending and **Health** on |
| Location history: a point each 100 m you move | Your Relay server's database | With sending and **Location history** on |
| A copy of the notes on your server | The phone's own storage | Kept when you turn sending off |
| The phone's key | The iPhone Keychain or the Android Keystore | Never sent, except as the key's headers |

With sending off, the app makes no network call, reads no health data, and keeps no location history.

Your Relay server is a private site behind a login. Only its owner, and the devices with keys, reach it. A key reaches only Relay's routes: [Keys](../api/keys/).

## What is not kept

- The Relay app has no ads and no analytics. It sends your notes, health and places only to your Relay server, and only with sending on.
- To name a place, such as a street, the phone uses its own address lookup from Apple or Google, only with sending on. That lookup gets the place's coordinates, not the note. With sending off, a pinned note shows **Pinned**.
- This website keeps no cookies and counts no visits. It is static pages, and it can't reach your server.

## Turn each part off

| Part | How |
|---|---|
| Everything sent | Turn off **Send to your Relay server** in [Settings](../app/settings/). Health and location stop, and what of them did not go yet is deleted. |
| Pins on typed notes | Turn off **Pin notes to where I am** in Settings. |
| Location history | Turn off **Location history** in Settings. |
| Health | Turn off **Health** in Settings, and take back the permission in Apple Health or Health Connect. |
| One phone | Tap **Disconnect this phone** in Settings, or turn its key off: [Keys](../api/keys/#make-list-and-turn-off-keys). |
| Ring notes | Turn off the webhook in the Pebble app, or turn off the Pebble app's key. |

Turning a part off stops new data. Data already on your server stays there, and your notes stay on your phone.
