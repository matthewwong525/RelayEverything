---
title: Health
description: Send your steps, heart rate, sleep, workouts, weight, blood pressure and more from Apple Health or Health Connect to your Relay Everything server.
---

Relay Everything can keep your health data beside your notes. It reads it from Apple Health on an iPhone, or from Health Connect on Android.

## What it reads

| Type | Sent as | A day's total |
| --- | --- | --- |
| Steps | count | the day's steps |
| Heart rate | bpm | lowest, average and highest |
| Sleep | minutes | the night's sleep |
| Workouts | minutes | how many, and their minutes |
| Weight | kg | the latest |
| Resting heart rate | bpm | average |
| Heart rate variability | ms | average |
| Blood oxygen | % | lowest and average |
| Blood pressure | mmHg, upper and lower | each reading |
| Cycle | flow: none, light, medium or heavy | the flow that day |
| Mindful minutes | minutes | total |
| Water | ml | total |

Mindful minutes come from an iPhone only: Health Connect does not give them to the app yet. Heart rate variability keeps the phone's own measure, because the two can't be compared: an iPhone sends SDNN (`hrv_sdnn`), and Android sends RMSSD (`hrv_rmssd`).

## Turn it on

1. Open **Settings**.
2. Turn on **Send to Relay Everything**, if it is off: [Connect a phone](../../start/connect-a-phone/). Health works only with sending on, and the app reads no health data while it is off.
3. Turn on **Health**.
4. Allow the phone to read the types you want. The phone shows a switch for each type, so you can leave any type off, such as cycle. The app skips a type you leave off, with no error. On Android, also allow Health Connect to read in the background and to read past data.

The phone asks for this only when you turn on **Health**. After an update that adds types, the app asks once more, for the new types only.

## 90 days of history

When you turn on **Health**, the app sends the last 90 days, so your AI has history at once. It sends the newest week first, then one older week each round, until it reaches 90 days. New readings always go first, so they never wait behind history. The app sends nothing older than 90 days.

A phone that already sent health gets the same 90 days one time after the update, for every type.

## When it sends

The app sends new health data each time you open it. While it is closed, it sends too:

- **On an iPhone**, Apple Health wakes the app when it has new readings, about once an hour. A locked iPhone keeps Health closed, so the readings go after you next unlock it.
- **On Android**, the app sends every hour while the phone lets it run.

Under **Health**, **Settings** shows when the data last went, and how many readings wait, such as *Sent 14:05 · 3 readings waiting*. Open the app to send at once.

Each sample is kept once for its type, time and source, however often the phone sends it.

## A day's totals

The server counts each day's totals, as the table in [What it reads](#what-it-reads) shows. When two devices count the same steps, sleep, mindful minutes or water, such as a phone and its watch, the day takes the larger count, not the sum. A day leaves out a type that has no readings that day.

## Turn it off

Turn off **Health** in **Settings**. The phone stops sending. Turning off **Send to Relay Everything** also stops health, and deletes the health data that did not go yet. To take back the phone's permission, use Apple Health or Health Connect. [Privacy](../../privacy/) says what the server keeps.
