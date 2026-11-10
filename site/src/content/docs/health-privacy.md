---
title: Health data policy (draft)
description: The health data policy for the shared Relay Everything server, a draft that is not in force. It says what health and location data is kept, why, who gets it, and how you agree, see and delete it.
---

:::caution[Draft: not in force]
This page is a draft for review. It has gaps, marked `[LEGAL-TODO: …]`, and it does not apply to you yet. The [Privacy](../privacy/) page says what Relay Everything keeps today.
:::

**In force from:** [LEGAL-TODO: start date]

This policy is for the health and location data on the shared Relay Everything server at [app.relayeverything.com](https://app.relayeverything.com). [LEGAL-TODO: company legal name] runs it. Washington state's [My Health My Data Act](https://app.leg.wa.gov/RCW/default.aspx?cite=19.373) asks for a policy of its own for health data. That law can count where you go as health data, so this policy treats your location history as health data too. The [Privacy policy](../privacy-policy/) covers all your other data.

## The health data we keep

Only the types you allow, and only while you are signed in and the part's own switch is on:

- **Health:** steps, heart rate, sleep, workouts, weight, resting heart rate, heart rate variability, blood oxygen, blood pressure, cycle, mindful minutes and water. [Health](../app/health/#what-it-reads) says what the app reads.
- **Location history:** a point each 100 m you move. [Location](../app/location/#location-history) says how it works.
- **A note's place:** where you were when you saved a note, if you turn on **Pin notes to where I am**.

Health notes that you type yourself are notes, and the [Privacy policy](../privacy-policy/) covers them.

## Why we keep it

We keep your health and location data only to show it to you, and to send it where you tell it to go. We never sell it, never use it for ads, never use it to train AI, and never use it to guess things about you. Apple's rules for the App Store, which we follow, also forbid the use of health data for ads: [App Review Guidelines, health and health research](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).

## Who it goes to

- **Cloudflare** runs the shared server, so it keeps your space: [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/).
- **The webhooks you tick for it.** A webhook gets health, calendar or location data only if you tick that kind for it: [Your own database](../connections/your-database/).
- **The AI apps you connect** read it only when they ask: [Connect your AI](../connections/connect-your-ai/).
- **Your own webhook only**, when you pick **Send to my own webhook instead** in the app, or, signed in, **Only my own webhook** for health, places, calendar and photos: then the phone sends it straight there, and the shared server gets none of it from then on. What it got before stays until you delete it.

No one else gets it, unless a court order or the law makes us give it.

## How you agree

You agree in two steps, and you can take back each one at any time:

1. In the app, you sign in from the [Account](../app/settings/#account) row in Settings, then turn on **Health** or **Location history** in its folder on Home.
2. Your phone asks you to allow it: Apple Health or Health Connect for each health type, and the phone's location permission for location history.

With either step off, the app reads none of that data and keeps none of it.

## See or delete it

- **See it** through your AI apps, your webhooks and your API keys.
- **Stop it:** turn off **Health** or **Location history** in its folder on Home, and take back the permission in the phone's settings. New data stops, and what is in your space stays until you delete it. The [Privacy](../privacy/#turn-each-part-off) page shows each step.
- **Delete it:** [delete your account](../privacy/#delete-your-account), and all your health and location data goes with it. The [Privacy policy](../privacy-policy/#how-long-we-keep-it) says how long Cloudflare's recovery copies keep it after that.
- **Ask us** to confirm what we keep, give you a copy, or delete it: write to the contact address on the shared server's sign-in screen. We answer within 45 days, and do not charge you.

## Changes to this policy

When this policy changes, this page shows the change with a new date. For a change that uses your health or location data in a new way, we ask for your consent first.
