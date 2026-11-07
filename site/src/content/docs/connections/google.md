---
title: Connect Google
description: Let your AI apps and API keys read and send your Gmail, change your Google Calendar and Drive files, and find your contacts, through Relay Everything.
---

Connect Google one time on your Relay Everything page. Then the AI apps you connected and the API keys you made can reach your Gmail, Google Calendar, Google Drive and Google Contacts. Relay Everything passes each request to Google and gives back Google's answer. It keeps no email, event, file or contact.

## Connect

1. On your Relay Everything page, find the **Google** card below **AI apps**, and click **Connect Google**.
2. Pick your Google account.
3. Until Google finishes its check of Relay Everything, Google shows a page that says *Google hasn't verified this app*. Click **Advanced**, then **Go to Relay Everything**.
4. Allow all of Gmail, Calendar, Drive and Contacts. Then you come back to your page, and the card shows **Connected** with your Google address.

When you cancel at Google, nothing changes. When you leave out a permission, the card says *Allow Gmail, Calendar, Drive and Contacts to connect*, and nothing is kept: click **Connect Google** again and allow all four.

An AI app you connected before you connected Google can't reach it. Disconnect the app on the **AI apps** card and [connect it again](../connect-your-ai/). The consent page then names Google.

## What the AI can do

The AI connector adds fourteen tools. Each one reaches only your own Google.

| Service | Tools |
|---|---|
| Gmail | **search_email** and **read_email** read. **send_email** sends from your address, **draft_email** puts a draft in your drafts, and **change_email** archives, marks read, labels or puts in the bin. |
| Calendar | **list_events** reads. **add_event**, **change_event** and **delete_event** change your calendar, and your guests get Google's emails. |
| Drive | **search_files** finds files, and **read_file** reads Docs, Sheets, Slides and text files. It can't read a PDF or an image: it gives the file's Drive link. **save_file** saves a new Doc or text file, and **change_file** renames, moves or puts in the bin. |
| Contacts | **find_contact** reads your contacts and the people you email. |

**A sent email can't be undone.** The AI app asks you before it uses **send_email** or **delete_event**: answer with care. To check an email first, ask for a draft.

Nothing deletes an email, a thread, a draft or a Drive file for ever. **change_email** and **change_file** put it in the bin, where Google keeps it 30 days.

A tool gives at most 20,000 characters of an email or a file, and at most 25 results a page.

## From a script

An API key reaches Google under `/v1/google/`, on your AI connector's address. Send Google's own path after the service:

| Service | Address | Google's path after |
|---|---|---|
| Gmail | `/v1/google/gmail/…` | `gmail/v1/users/me/` |
| Calendar | `/v1/google/calendar/…` | `calendar/v3/` |
| Drive | `/v1/google/drive/…`, and `/v1/google/drive/upload/…` to upload | `drive/v3/` |
| Contacts | `/v1/google/contacts/…`, GET only | `v1/` of the People API |

```sh
curl "https://<your-relay-server>/v1/google/calendar/calendars/primary/events?timeMin=2026-11-05T00:00:00Z&singleEvents=true" \
  -H "Authorization: Bearer rek_…"
```

The answer is Google's own: its status, type and body. Google's [Gmail](https://developers.google.com/workspace/gmail/api/reference/rest), [Calendar](https://developers.google.com/workspace/calendar/api/v3/reference), [Drive](https://developers.google.com/workspace/drive/api/reference/rest/v3) and [People](https://developers.google.com/people/api/rest) references list each path. Relay Everything refuses a delete for ever, and Gmail paths start after `users/me/`, so you reach only your own mail. [Connect a service](../../api/connect-a-service/#google) tells more.

## What is kept

Your space keeps your Google address, the permissions you gave, when you connected, and Google's sign-in for Relay Everything, sealed with your space's own key. Nothing else from Google is kept. A short Google token stays in the server's memory for up to one hour.

When an AI app uses a tool, Google's answer goes to that app's company, as [Connect your AI](../connect-your-ai/#what-leaves-relay-everything) tells. Relay Everything's use and transfer of information received from Google APIs to any other app will adhere to the [Google API Services User Data Policy](https://developers.google.com/terms/api-services-user-data-policy), including the Limited Use requirements. [Privacy](../../privacy/#google) tells more.

## Disconnect

On the **Google** card, click **Disconnect**, then confirm. Relay Everything ends its sign-in at Google and deletes it from your space. The next request from an AI app or a key is refused. You can also remove Relay Everything at [your Google account's connections](https://myaccount.google.com/connections): the next request then finds no sign-in, and the card shows **Connect Google** again.

Deleting your Relay Everything account also disconnects Google.
