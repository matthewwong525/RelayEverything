---
title: Email notes
description: Forward or write an email to your own notes address, and it becomes a note in your space, with its files.
---

Relay Everything gives you your own secret notes address. Any mail to it becomes a note in your space, whoever sends it. Forward a receipt, write yourself a reminder, or set a mail rule that forwards each receipt on its own. No mail is ever sent back.

Email notes work on a server that takes email: the shared server, or [your own server](../../start/run-your-own/#take-email) with a mail domain set. With email off, Settings on your Relay Everything page has no **Email notes** page.

## Find your address

1. Sign in on your Relay Everything page, `<your-relay-server>/`.
2. Click **Settings** at the bottom of the left bar, then **Email notes**. Your address starts with `notes-` and ends with your server's mail domain.
3. Click **Copy**, and add the address to your contacts or to a mail rule.

Keep the address private. Anyone who has it can add notes to your space.

## Write from your sign-in email

You can also write to the shared address, `notes@` and your server's mail domain, as the **Email notes** page shows. Mail to it becomes a note only when it comes from the email you sign in with, and only when it passes the sender checks: DMARC, or SPF and DKIM. Mail that fails the checks is dropped with no answer, so nobody can add notes in your name.

Mail to `notes@` from an email with no account yet is kept, sealed, for 30 days. When that email signs up, the kept mail becomes notes, each at the time it was sent. After 30 days, kept mail is deleted. Each email can have up to 100 kept messages and 50 MB; past that, the oldest is deleted.

## What a note keeps

| From the mail | In the note |
|---|---|
| The subject | The first line |
| The words | The rest of the note. A reply's quoted mail is cut; a forwarded mail stays whole. A mail with only HTML gives its words, with no look. |
| Attached files | The note's files, up to 10, each up to 25 MB. A larger or extra file is left out, and the note names it. A picture pasted into the mail's words is a file too, when it is 20 KB or more. A smaller one, such as a logo, is part of the mail's look: it is left out, and the note does not name it. |
| When it was sent | The note's time |

Each emailed note comes from the device **Email**. Your webhooks, your AI apps and the web API see where it came from by that name. [Your own database](../../connections/your-database/)

The same mail sent twice makes one note.

## Replace your address

If your address leaks, click **New address** on the **Email notes** page in Settings, then **New address** again to confirm. Mail to the old address makes no note from now on. Change the address in your mail rules and contacts.

## What is sent

:::caution
Email is not sealed on the way. Don't send health or location details this way.
:::

Mail goes through the sender's mail service and Cloudflare Email Routing before it reaches your server. Each one can read it on the way. Your server then keeps the note and its files in your space, the same as a note from the phone, with each file sealed. [Privacy](../../privacy/)
