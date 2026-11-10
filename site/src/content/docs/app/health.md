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
| Sleep | minutes, and each night's stages | the night's sleep |
| Workouts | minutes, kind, km and calories | how many, and their minutes |
| Weight | kg | the latest |
| Resting heart rate | bpm | average |
| Heart rate variability | ms | average |
| Blood oxygen | % | lowest and average |
| Blood pressure | mmHg, upper and lower | each reading |
| Cycle | flow: none, light, medium or heavy | the flow that day |
| Mindful minutes | minutes | total |
| Water | ml | total |

Mindful minutes come from an iPhone only: Health Connect does not give them to the app yet. Heart rate variability keeps the phone's own measure, because the two can't be compared: an iPhone sends SDNN (`hrv_sdnn`), and Android sends RMSSD (`hrv_rmssd`).

## Nights and workouts

The app makes each night from the phone's sleep readings: when you went to bed, fell asleep and woke, the minutes of core (light), deep and REM sleep and of awake time, and the timeline of stages. A watch gives the stages. A phone with only your bedtime gives a night with no stages. Each app or watch makes its own night, and your AI reads the one with the most sleep. A nap is a night of its own.

Each workout goes with its kind, such as running, and its distance and calories when the phone has them. An iPhone gives active calories. Android gives total calories, which also count the calories you burn at rest.

On Android, the app also asks to read distance and total calories. Health Connect gives the app workouts only with them: if you refuse, the app sends no workouts from Android. Allow both in Health Connect to send them.

## Turn it on

1. Open **Health**, under **On this phone** on Home.
2. If you are signed out, tap **Sign in**: [Connect a phone](../../start/connect-a-phone/). Health works only once you sign in, and the app reads no health data while you are signed out.
3. Turn on **Health**.
4. Allow the phone to read the types you want. The phone shows a switch for each type, so you can leave any type off, such as cycle. The app skips a type you leave off, with no error. On Android, also allow Health Connect to read in the background and to read past data.

The phone asks for this only when you turn on **Health**. After an update that adds types, the app asks once more, for the new types only.

## 90 days of history

When you turn on **Health**, the app sends the last 90 days, so your AI has history at once. It sends the newest week first, then one older week each round, until it reaches 90 days. New readings always go first, so they never wait behind history. The app sends nothing older than 90 days.

A phone that already sent health gets the same 90 days one time after the update, for every type.

After the update that adds nights, the app reads the last 90 days of sleep and workouts one more time, one week each round. Your old nights then get their stages, and your old workouts their kind, distance and calories. Nothing goes twice: Relay Everything keeps each reading once. When the app sends to [your own webhook](../../connections/your-database/), a reading that goes again has the same id. A reading the app sent there before this update had a different id, so keep one reading for each device, type, start, end and source. The [example receiver](../../connections/your-database/#an-example-receiver) does this.

## When it sends

The app sends new health data each time you open it. While it is closed, it sends too:

- **On an iPhone**, Apple Health wakes the app when it has new readings, about once an hour. A locked iPhone keeps Health closed, so the readings go after you next unlock it.
- **On Android**, the app sends every hour while the phone lets it run.

The **Health** folder, and its row on Home, show when the data last went, and how many readings wait, such as *Sent 14:05 · 3 readings waiting*. Open the app to send at once.

Each round reads sleep and workouts from the last 36 hours, because a watch writes the whole night when you wake. A night or workout that did not change does not go again.

Each sample is kept once for its type, time and source, however often the phone sends it.

## A day's totals

The server counts each day's totals, as the table in [What it reads](#what-it-reads) shows. When two devices count the same steps, sleep, mindful minutes or water, such as a phone and its watch, the day takes the larger count, not the sum. A day leaves out a type that has no readings that day.

## Only to your own webhook

Signed in to Relay Everything, you can send your health data only to your own webhook and still sync your notes. On the **Account** page, under **Advanced**, open **Webhooks** and turn on **Only to my own webhook**. The phone then sends each reading straight to your receiver as `health.samples`, and each night as `health.nights`, and Relay Everything gets none. The **Health** folder then says *Sent to your webhook* and the time. Your AI shows no new readings, and the readings already sent stay in your space. [Settings](../settings/#health-places-calendar-and-photos-only-to-your-webhook)

## Turn it off

Turn off **Health** in the **Health** folder. The phone stops sending. Signing out also stops health, and deletes the health data that did not go yet. To take back the phone's permission, use Apple Health or Health Connect. [Privacy](../../privacy/) says what the server keeps.
