# Design

## Context

See [proposal.md](proposal.md) for why. Today `AccountPage._webhook` (`mobile/lib/screens/account.dart`) shows the webhook, *Notes from elsewhere* (opens `#webhooks` on the web page) and *Stop sending*. `choosePlace` (`mobile/lib/screens/folder.dart`) is the one sign-in flow: it opens `ConnectScreen`, asks about earlier notes with `_EarlierDialog`, then calls `relay.startSending(place:)`. `accountOf` reads `settings.place`, so the page switches to the signed-in view once `place` is `server`.

`Settings.privatePlace` already routes private data: whole-webhook mode returns `webhook`; otherwise it returns `privateTo`. `setPrivatePlace(webhook)` needs a kept webhook, which a webhook-mode phone always has.

Earlier notes today are `store._earlier`: `sent_at IS NULL AND queued = 0`. A note sent to the webhook has `queued = 1` and `sent_at` set (`outbox.dart` calls `noteSent` for every `notes` item, whatever the place), so it never counts. The server keeps a note once per `(device_id, client_id)`; a new sign-in makes a new device key.

## Goals / Non-Goals

**Goals:** one tap from the webhook Account page into the existing sign-in; one settings write that moves notes to the server and keeps private data on the webhook; the earlier-notes question covers notes that went only to the webhook.

**Non-Goals:** a new sign-in screen; telling the server about the phone's webhook; any server change.

## Decisions

- **Reuse `choosePlace`, with a `privateTo` option.** `choosePlace(context, relay, scanner, keepWebhook: true)` opens `ConnectScreen` with a new `signInOnly` flag, which hides *Send to my own webhook instead* (the phone is there already). On `SendPlace.server`, it calls `relay.startSending(place: server, privateTo: webhook, sendEarlier: …)`. Alternative: call `setPrivatePlace(webhook)` then `startSending(server)`. Rejected: two settings writes, two outbox moves and two sync rounds for one tap.
- **`startSending` gains `SendPlace? privateTo`.** It folds into the same `copyWith`, so `_moveOutbox` sees the final settings once: waiting notes move to the server; waiting health, places and calendar stay on the webhook. A webhook-mode phone already sends private data to the webhook, so the calendar's sent list is kept, not dropped.
- **Earlier notes from the webhook: a second store query, used only for this move.** `earlierCount({bool fromWebhook})` and `queueEarlier({bool fromWebhook})` add own notes (`mine = 1`) with `server_id IS NULL`, `sent_at IS NOT NULL`, no pending words or pin, and not being deleted. `Relay.earlierNotes` and `startSending` pass `fromWebhook` when the phone's current place is `webhook` and the new place is `server`. Queuing sets `queued = 1` as today, so a second sign-in never asks again once the note has a server id. Alternative: clear `sent_at` on every note when the place changes. Rejected: it would also re-ask about notes already on the server.
- **`_EarlierDialog` says where the notes went.** With `fromWebhook`, its text is *They are not on Relay Everything yet.* (true for notes sent to the webhook and for notes that never left the phone) in place of *They were only on this phone.*; the rest stays.
- **The message after sign-in is a `SnackBar`.** The Account page shows it when `choosePlace` returns with `server` from this row. It needs no saved state, and it never shows again.
- **`AccountPage` takes the `scanner`.** Settings passes its `Scanner?` through, as it does to `choosePlace`, so the row can open *Scan a key* too.

## UX

- **Who and the job:** a person who set up their own webhook with no account, and now wants notes on their other phones or their AI. Done is: signed in, notes syncing, private data still only on their webhook. It happens once per phone, on the phone.
- **Shortest flow:** Settings → Account → *Sign in to Relay Everything* → sign in → (earlier notes question, if any) → back on Account, signed in, with a message.
- **Hierarchy:** the webhook page keeps no filled button; the new row is a plain row with a chevron, as *Open your Relay Everything page* is on the signed-in page. *Stop sending* stays last, in red.
- **Components:** existing `Group` and `ListTile`; the existing `ConnectScreen`, `_EarlierDialog` and `SnackBar`. Mirrors the signed-in Account page.

### Review

[review.html](review.html) sketches the webhook Account page, the earlier-notes question and the message in What Changes bullets 1, 3 and 4.

## Risks / Trade-offs

- **A note sent to Relay Everything under an old key, then never pulled, has no server id** → it is offered again and could make a second copy. Rare: a pull gives each own note its server id. Accepted.
- **The webhook stops getting notes from the phone** → the row's subtitle and the message say so, and the website explains adding the webhook on the page.
- **The iPhone check has no account** → widget tests cover the signed-in result; the iPhone check's Settings tour saves a webhook (the save checks only the address's form, with no network) and shows the new row.
