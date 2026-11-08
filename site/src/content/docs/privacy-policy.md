---
title: Privacy policy (draft)
description: The privacy policy for the shared Relay Everything server, a draft that is not in force. It says who keeps your data, why, who handles it, how long, and your rights.
---

:::caution[Draft: not in force]
This page is a draft for review. It has gaps, marked `[LEGAL-TODO: …]`, and it does not apply to you yet. The [Privacy](../privacy/) page says what Relay Everything keeps today.
:::

**In force from:** [LEGAL-TODO: start date]

This policy is for the shared Relay Everything server at [app.relayeverything.com](https://app.relayeverything.com), and for the Relay Everything app when it sends to that server. On [your own server](../start/run-your-own/), you keep the data, and this policy does not apply to it. The [Health data policy](../health-privacy/) adds the rules for your health and location data.

## Who we are

[LEGAL-TODO: company legal name], a company in Ontario, Canada, runs the shared server. Its address is [LEGAL-TODO: postal address]. In this policy, *we* means that company.

**The person in charge of privacy** is the company's owner. To reach them, write to the contact address on the shared server's sign-in screen, [app.relayeverything.com](https://app.relayeverything.com). It is also on your account card when you are signed in.

## What we keep

The [Privacy](../privacy/#what-is-kept-and-where) page lists each kind of data, where it is kept, and when it is sent. It is the one list: this policy does not copy it. In short:

- **Your account:** your email, how you sign in, and a fingerprint of each key and sign-in.
- **What you send:** your notes and their files, voice note words, health, calendar events, location history and photos, only with **Send my notes** on, and only the parts you turn on.
- **What you set:** your devices, webhooks, connected AI apps and chats.

We keep no ads data, no analytics, and no record of your visits to this website.

## Why we keep it

We use your data only to run the service for you: to keep it in your own space, show it to you, and send it where you tell it to go. Your consent is the switches you turn on, in the app and on your Relay Everything page.

- We never sell your data.
- We never use it for ads.
- We never use it to train AI, ours or anyone else's.
- We never open your space to read it. The [Privacy](../privacy/#who-can-see-what) page says who can see what, and the limit of that promise.

## Who handles it for us

These services handle data so that the shared server works. Each one has its own privacy policy.

| Service | What it does | What it gets | Its policy |
|---|---|---|---|
| Cloudflare | Runs the shared server: its code, your space, the account list, the file store, the webhook queue, and the email that sends sign-in codes | All the data on the shared server | [Cloudflare's privacy policy](https://www.cloudflare.com/privacypolicy/) |
| Apple | **Continue with Apple**; on an iPhone, Apple Health and the phone's address lookup | Your sign-in with Apple; the coordinates of a place to name | [Apple's privacy policy](https://www.apple.com/legal/privacy/) |
| Google | **Continue with Google**; on Android, Health Connect and the phone's address lookup | Your sign-in with Google; the coordinates of a place to name | [Google's privacy policy](https://policies.google.com/privacy) |
| Hugging Face | Gives the speech model for voice notes, one time, after you tap **Get it** | The phone's internet address, as with any download, and no note | [Hugging Face's privacy policy](https://huggingface.co/privacy) |

Apple Health and Health Connect keep your health data on your phone. The app reads it there, and sends it only to your space.

Cloudflare can keep and handle data in other countries, such as the United States. The laws of those countries can let their courts and governments ask Cloudflare for it.

## Where it goes only when you send it

Your data goes to these places only when you add them, and only the parts you pick:

- **Your AI apps**, such as Claude from Anthropic or ChatGPT from OpenAI, read your space after you connect them: [Connect your AI](../connections/connect-your-ai/). What they do with it is under their own policies.
- **Your webhooks** get a copy of what your space keeps, at the addresses you add: [Your own database](../connections/your-database/).
- **Your own scripts and services** read your space with an API key you made: [Connect a service](../api/connect-a-service/).

We give your data to no one else, unless a court order or the law makes us. When the law lets us, we tell you first.

## How long we keep it

- Your data stays in your space until you delete it or [delete your account](../privacy/#delete-your-account).
- When you delete your account, your space, files and keys go at once. Cloudflare's recovery copies can hold them for up to 30 days more, and then they are gone: Cloudflare can restore a space to [any point in the past 30 days](https://developers.cloudflare.com/durable-objects/api/sqlite-storage-api/#pitr-point-in-time-recovery-api), and the account list to [any minute in the past 30 days](https://developers.cloudflare.com/d1/reference/time-travel/). We use those copies only to repair the server after a fault.
- A sign-in code works for 10 minutes. A sign-in in your browser lasts 30 days.
- When we shut the shared server down, we give 30 days' notice on this website, then delete all data.

## Your rights

You have these rights wherever you live. Canada's privacy law for companies, the [Personal Information Protection and Electronic Documents Act (PIPEDA)](https://www.priv.gc.ca/en/privacy-topics/privacy-laws-in-canada/the-personal-information-protection-and-electronic-documents-act-pipeda/), gives them to people in Canada, and Quebec's [Law 25](https://www.cai.gouv.qc.ca/) adds rules for people in Quebec.

- **See your data:** your Relay Everything page shows it, and your webhooks and API keys get a copy of it. You can also ask us for a copy.
- **Correct it:** ask us to correct your account's data.
- **Delete it:** [delete your whole account](../privacy/#delete-your-account), or ask us to delete a part of your data.
- **Take back your consent:** turn off a part in the app's [Settings](../app/settings/), or turn off **Send my notes**. The [Privacy](../privacy/#turn-each-part-off) page shows how.
- **Complain:** write to us first. If our answer does not satisfy you, you can complain to the [Office of the Privacy Commissioner of Canada](https://www.priv.gc.ca/en/report-a-concern/), or to the privacy office where you live.

To ask, write to the contact address on the shared server's sign-in screen. We answer within 30 days. We can ask you to show that the account is yours, such as by writing from its email.

## Children

You must be 18 or older to use the shared server. We do not knowingly keep data from a person under 18. If we learn that we do, we delete that account.

## Security

Each person's data is in their own space, and each file is sealed with a key kept in that space. The [Privacy](../privacy/#who-can-see-what) page says how, and what it does not stop. If a breach puts your data at risk, we tell you and the Office of the Privacy Commissioner of Canada as the law asks.

## Changes to this policy

When this policy changes, this page shows the change with a new date. For a change that uses your data in a new way, we ask for your consent first.
