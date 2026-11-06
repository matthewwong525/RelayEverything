---
title: Health
description: Send your steps, heart rate, sleep and workouts from Apple Health or Health Connect to your Relay Everything server.
---

Relay Everything can keep your steps, heart rate, sleep and workouts beside your notes. It reads them from Apple Health on an iPhone, or from Health Connect on Android.

## Turn it on

1. Open **Settings**.
2. Turn on **Send to Relay Everything**, if it is off: [Connect a phone](../../start/connect-a-phone/). Health works only with sending on, and the app reads no health data while it is off.
3. Turn on **Health: steps, heart rate, sleep, workouts**.
4. Allow the phone to read steps, heart rate, sleep and workouts. On Android, also allow Health Connect to read in the background.

The phone asks for this only when you turn on **Health**. The app reads from that moment on, not from before.

## When it sends

The app sends new health data each time you open it, and every hour while it can run. An iPhone runs background work when it chooses, so open the app to send at once.

Each sample is kept once for its type, time and source, however often the phone sends it.

## A day's totals

The server counts each day's steps, sleep, heart rate and workouts. When two devices count the same steps, such as a phone and its watch, the day takes the larger count, not the sum.

## Turn it off

Turn off **Health** in **Settings**. The phone stops sending. Turning off **Send to Relay Everything** also stops health, and deletes the health data that did not go yet. To take back the phone's permission, use Apple Health or Health Connect. [Privacy](../../privacy/) says what the server keeps.
