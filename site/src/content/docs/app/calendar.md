---
title: Calendar
description: Send the events of your phone's calendars to your Relay Everything server, so your AI knows your day and who you meet.
---

Relay Everything can keep your phone's calendar events beside your notes, so your AI knows your day and who you meet. It reads every calendar on the phone: Google, iCloud, Outlook, work and subscribed calendars. You need no Google sign-in. The app only reads: it never adds, changes or deletes an event.

## Turn it on

1. Open **Calendar**, under **On this phone** on Home.
2. If you are signed out, tap **Sign in**: [Connect a phone](../../start/connect-a-phone/). The calendar works only once you sign in, and the app reads no calendar while you are signed out.
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

Under **Calendars**, the **Calendar** folder lists each calendar on the phone, each with its own switch. All are on at first. Turn one off, such as a holiday calendar. At the next send, its events are removed from your space.

## When it sends

The app sends calendar changes each time you open it. On Android, it also sends every hour while the phone lets it run. On an iPhone, it also sends when Apple Health or your places wake the closed app.

The **Calendar** folder shows when the events last went, such as *Sent 10:42 · none waiting*. Its row on Home shows how many calendars are on, such as *2 calendars · Sent 10:42*.

## Where your events go

Your events go where your health and places go. With **My own webhook**, the phone sends them straight to your receiver as [`calendar.events`](../../connections/your-database/#send-from-the-phone), and your server gets none. When you change the place, the phone sends the whole window to the new place.

Signed in to Relay Everything, you can also turn on **Only to my own webhook** in **Webhooks**, under **Advanced** on the **Account** page. Your notes still sync through Relay Everything, and your events go only to your receiver as `calendar.events`. The **Calendar** folder then says *Sent to your webhook* and the time. When you turn it off again, the phone sends the whole window to Relay Everything. [Settings](../settings/#health-places-calendar-and-photos-only-to-your-webhook)

With **Relay Everything**, your events go only to your own space on your server. From there:

- your AI reads them with the **calendar** tool: [Connect your AI](../../connections/connect-your-ai/)
- your scripts read them at `GET /v1/calendar`: [Connect a service](../../api/connect-a-service/)
- a webhook you tick for **Calendar** gets each new, changed and removed event: [Your own database](../../connections/your-database/)

## Turn it off

Turn off **Calendar** in the **Calendar** folder. The phone stops reading and sending, and deletes the events that did not go yet. When you turn it on again, the app sends the whole window again. Signing out also stops the calendar. To take back the phone's permission, use the phone's settings. [Privacy](../../privacy/) says what the server keeps.
