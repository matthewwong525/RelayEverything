---
title: Privacy
description: What Relay keeps, where it keeps it, and how to turn each part off.
---

Relay keeps your notes, health and places on your own Relay server, and nowhere else. This website holds none of them.

## What is kept, and where

| What | Where | Sent when |
|---|---|---|
| Ring notes: the words and the recording | Your Relay server: the words in its database, the recording in its file store | Each time you hold the ring and talk |
| Typed notes, with their place | Your Relay server's database | Each time you save a note |
| Steps, heart rate, sleep and workouts | Your Relay server's database | On open and every hour, with **Health** on |
| Location history: a point each 100 m you move | Your Relay server's database | With **Location history** on |
| Notes not sent yet, and a copy of your notes | The phone's own storage | Until they are sent |
| The phone's key | The iPhone Keychain or the Android Keystore | Never sent, except as the key's headers |

Your Relay server is a private site behind a login. Only its owner, and the devices with keys, reach it. A key reaches only Relay's routes: [Keys](../api/keys/).

## What is not kept

- The Relay app has no ads and no analytics. It sends your notes, health and places only to your Relay server.
- To name a place, such as a street, the phone uses its own address lookup from Apple or Google. That lookup gets the place's coordinates, not the note.
- This website keeps no cookies and counts no visits. It is static pages, and it can't reach your server.

## Turn each part off

| Part | How |
|---|---|
| Pins on typed notes | Turn off **Pin notes to a place** in [Settings](../app/settings/). |
| Location history | Turn off **Location history** in Settings. |
| Health | Turn off **Health** in Settings, and take back the permission in Apple Health or Health Connect. |
| One phone | Tap **Disconnect this phone** in Settings, or turn its key off: [Keys](../api/keys/#make-list-and-turn-off-keys). |
| Ring notes | Turn off the webhook in the Pebble app, or turn off the Pebble app's key. |

Turning a part off stops new data. Data already on your server stays there.
