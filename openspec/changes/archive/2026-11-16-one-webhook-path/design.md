# Design: one path to your webhook

## Context

See proposal.md, Why. Since `private-data-to-own-webhook` (2026-11-09), `Settings` has `place` (where notes go) and `privateTo` (where health, places, calendar and photos go while signed in); `privatePlace` derives the second. The store keeps two outbox destinations, `outbox.destination` and `outbox.private`, and routes `health`, `locations` and `calendar` rows by the second at enqueue. `Sender.privateApi` gives a second client, and `Controller._sync` and `backgroundRound` flush twice and send photos through the private client. `sign-in-from-webhook` added `keepWebhook` to `choosePlace`, so a sign-in from the webhook Account page sets `privateTo: webhook`.

The server already takes every kind and sends each on only to the webhooks ticked for it, and `POST webhooks/backfill` sends past data to a webhook. No server change is needed.

## Goals / Non-Goals

**Goals:** one destination per phone: `relay-server` while signed in, `webhook` with no account. A phone with `privateTo: webhook` moves to the server once, at load, and shows one message.

**Non-goals:** a server change; adding the phone's webhook to the person's page; any change to the no-account webhook mode.

## Decisions

### Remove the second place, not hide it

`privateTo`, `privatePlace`, `Sender.privateApi`, `Relay.setPrivatePlace`, `Relay.privateWebhookMissing`, `startSending(privateTo:)`, `choosePlace(keepWebhook:)`, `ConnectScreen(privateOnly:)` and `flush(private:)` go. Every reader of `privatePlace` reads `place`. Photos go through `api`.

*Alternative:* keep the field and force it to `server`. Rejected: dead branches in the sender and two flushes would stay, and a later change could switch them back on by mistake.

### The move happens at load, with a one-time flag

`Settings.decode` stops reading `privateTo`. A static `Settings.hadPrivateWebhook(saved)` answers true when the saved JSON has `privateTo: "webhook"` and `place` is not `webhook`. In `Controller.load`, when it is true and sending is on, the controller sets the store key `notice.throughServer` before it saves the settings in today's shape. The settings save drops `privateTo`, so the check is true only once.

`Store.moveOutbox(destination)` takes one destination. When a kept `outbox.private` differs from the new destination, it drops the calendar's sent list and the sent times of health, points and the calendar, as today, so the server gets the calendar's whole window. Then it removes `outbox.private` and sets every row to `destination`. `load` calls it when `outbox.private` exists or `outbox.destination` differs. The rows waiting for the webhook keep their order and go to the server in the next round.

`Relay.throughServerNotice` reads the flag; `Relay.dismissThroughServerNotice()` removes it.

### The message is a dialog on Home

`HomeScreen`, in `home.dart`, shows an `AlertDialog` once after its first frame while `relay.throughServerNotice` is true. Title: *Everything now goes through Relay Everything*. Text: *This iPhone no longer sends health, places, calendar and photos straight to your webhook. They go to Relay Everything, then to each webhook you tick for them on your page.* (the device name from `relay.device`). *OK* dismisses it; *Open Webhooks* dismisses it and opens `WebhooksPage`. Both clear the flag, and so does closing it by a tap outside.

### The phone keeps its webhook

The vault keeps the webhook's address and secret while signed in, as it does today. After *Sign out*, *Don't want an account? Use your own webhook* finds them filled in. Signed in, `Sender.api` never builds a `WebhookClient`.

### Words

- `webhooks.dart` first line: *For developers. Your own server gets a copy of your notes, and of what else you tick for it, as they arrive. You do not need it to use Relay Everything.*
- `account.dart`, webhook Account page row: *Sync your notes with your page, your AI and your other phones. Everything then goes through Relay Everything: add your webhook on your page to keep getting it.*
- `connect.dart` with `signInOnly`: *Sign in to keep your notes the same on all your devices, and let your AI read them. This phone then sends everything to Relay Everything, health, places, calendar and photos too. To keep getting them at your webhook, add it on your Relay Everything page.*
- The message after that sign-in: *Signed in. To keep getting everything at your webhook, add it under Webhooks on your Relay Everything page.*
- Folder pages drop *Sent to your webhook*; while signed in they say *Sent*.

## UX

### Use-case brief

Two people. A signed-in person who runs their own receiver, such as WongOS: they add it once on their Relay Everything page, tick what it takes, and never think about which way each kind goes. A person with no account who keeps everything off our server: unchanged. The edge case: a phone that had *Only to my own webhook* on before the update. It sees one message, once, at the next open.

### Flow

Update → open the app → Home with the message → *OK*, or *Open Webhooks* → *Webhooks* list → *Add or change on your Relay Everything page* → the page's webhook form, where the person ticks health, places, calendar and photos.

No account → Account → *Sign in to Relay Everything* → *Sign in* (it says everything then goes to Relay Everything) → earlier-notes question → signed in, and a short message to add the webhook on the page.

### Hierarchy

The message has one filled button, *Open Webhooks*, because adding the webhook is the step the person most likely needs. *Webhooks* has no filled button: its link row is the one action. The Account page stays as it is.

### Review

[review.html](review.html). What Changes items 2, 3 and 4 show *Webhooks*, the message, the webhook Account page and the *Sign in* screen, before and after.

### Components

Existing: `Group`, `ListTile`, `AlertDialog`, `FilledButton`, `TextButton`, `WebhooksPage`, `ConnectScreen`. Nothing new.

## Risks / Trade-offs

- [A tester who chose *Only to my own webhook* now sends private data to our server without a new yes] → the person chose this outcome; the one-time message says it at the next open, and *Open Webhooks* is one tap. The background round may send before the app opens: accepted, as the update itself is the change.
- [The person's receiver stops getting health and the rest until they add it on the page] → the message and the sign-in words say so; the server's *send past data* fills the gap from any date.
- [A missed flag shows no message] → a controller test reads an old saved JSON and checks the flag, the moved rows and one dialog.

- [The recordings plan changes what a webhook gets for a voice note] → this change keeps both webhook paths and changes no message; whichever plan lands second checks that both paths carry recordings as files with their transcripts (task 5.2).

## Migration Plan

No server or table change. At the first load after the update, a phone with `privateTo: webhook` moves its waiting private rows to `relay-server`, drops `outbox.private`, saves its settings without `privateTo`, and sets the message flag. A phone that never had the choice only drops a matching `outbox.private` key. Rollback: an older build reads a missing `privateTo` as `server`, so it keeps sending to the server.
