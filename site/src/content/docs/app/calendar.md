---
title: Calendar
description: Send the events of your phone's calendars to your Relay Everything server, so your AI knows your day and who you meet.
---

Relay Everything can keep your phone's calendar events beside your notes, so your AI knows your day and who you meet. It reads every calendar on the phone: Google, iCloud, Outlook, work and subscribed calendars. You need no Google sign-in. The app only reads: it never adds, changes or deletes an event.

## Turn it on

1. Open **Settings**.
2. Turn on **Send my notes**, if it is off: [Connect a phone](../../start/connect-a-phone/). The calendar works only with sending on, and the app reads no calendar while it is off.
3. Turn on **Calendar**.
4. Allow the phone to read your calendars. On an iPhone, pick **Allow Full Access**.

The phone asks for this only when you turn on **Calendar**.

## What it sends

The first time, the app sends your events from 90 days ago to 90 days ahead. After that, it sends only the events that are new, changed or removed in that window. An older event stays in your space when it leaves the window: it happened.

Each event goes with:

- its title, start, end, and if it is all day
- its place, notes and link, when it has them
- the name of its calendar
- its people: each one's name and email, and who organized it

Each time of a repeating event, such as a weekly meeting, is its own event with its own start.

Your space keeps each event once, however often the phone sends it. When you move an event, your space shows its new time. When you delete an event, your space no longer lists it.

## Turn off one calendar

Under **Calendar**, **Settings** lists each calendar on the phone, each with its own switch. All are on at first. Turn one off, such as a holiday calendar. At the next send, its events are removed from your space.

## When it sends

The app sends calendar changes each time you open it. On Android, it also sends every hour while the phone lets it run. On an iPhone, it also sends when Apple Health or your places wake the closed app.

Under **Calendar**, **Settings** shows when the events last went, such as *Last sent 10:42 AM*.

## Where your events go

Your events go only to the place you pick in **Send my notes**. With **My own webhook**, the phone sends them straight to your receiver as [`calendar.events`](../../connections/your-database/#send-from-the-phone), and your server gets none. When you change the place, the phone sends the whole window to the new place.

With **Relay Everything**, your events go only to your own space on your server. From there:

- your AI reads them with the **calendar** tool: [Connect your AI](../../connections/connect-your-ai/)
- your scripts read them at `GET /v1/calendar`: [Connect a service](../../api/connect-a-service/)
- a webhook you tick for **Calendar** gets each new, changed and removed event: [Your own database](../../connections/your-database/)

## Turn it off

Turn off **Calendar** in **Settings**. The phone stops reading and sending, and deletes the events that did not go yet. When you turn it on again, the app sends the whole window again. Turning off **Send my notes** also stops the calendar. To take back the phone's permission, use the phone's settings. [Privacy](../../privacy/) says what the server keeps.
