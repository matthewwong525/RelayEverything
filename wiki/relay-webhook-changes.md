# Add a kind of data to Relay Everything

Each kind of data in a person's space, such as notes, health or the calendar, has one entry in [`app/worker/apps/relay/kinds.ts`](../app/worker/apps/relay/kinds.ts). The entry names all its parts: its webhook tick, its send log kinds and messages, its `/v1/` routes, its AI connector tools and its website page. To add a kind, add one entry. To give a kind a new part, change its entry.

## What reads the list

- The webhook sender, [`webhooks/send.ts`](../app/worker/apps/relay/webhooks/send.ts), builds each message with the `build` of the kind that owns the send log row.
- [`webhooks/log.ts`](../app/worker/apps/relay/webhooks/log.ts) makes `TAKES` from each kind's `log`.
- [`webhooks/routes.ts`](../app/worker/apps/relay/webhooks/routes.ts) takes the ticks from the list, and `GET webhooks` answers them in `kinds`. The webhook form and card, [`Webhooks.tsx`](../app/src/apps/relay/Webhooks.tsx), draw the ticks and kind names from that answer, so the web page holds no copy of the list.

## What the check finds

[`kinds.test.ts`](../app/worker/apps/relay/kinds.test.ts) fails, and names the kind and the part, when:

- A part is gone and the entry does not list it in `missing`, with the reason. For a webhook part, each message type needs its place in [`webhooks/format.ts`](../app/worker/apps/relay/webhooks/format.ts), a `###` heading on the website's *Your own database* page, and a branch in the example receiver, `site/public/webhooks/receiver.mjs`.
- A part listed in `missing` exists. Take it out of `missing` when a change adds the part.
- A message type or a send log kind has no owner, or two. Only `webhook.test` is shared.
- The `relay_outbox` CHECK list in the newest space migration is not the same as the kinds' `log` lists.

So add the entry first, and let the check list what the kind still needs. Files and Claude Code chats list their webhook part as missing until a plan adds it.

## A kind with a file

A kind whose message carries a file's bytes, as photos do with `photo.created`, follows the ring recording in `note.created`:

- Mark the kind `alone`, so each log row goes in a message of its own. A photo can be 3 MB, which is about 4 MB in base64.
- Read the bytes in its `build` through `files.open`, and send them with `base64` from [`webhooks/sign.ts`](../app/worker/apps/relay/webhooks/sign.ts).
- The route stores the row before the file, so the log row comes first. `build` answers "wait" while the file can still be saving, and "skip" when the row is gone or the file never came.
- Mark the kind `sensitive` when its data shows where a person was, as health, places, the calendar and photos do.
- The phone's own webhook mode sends the same message from [`mobile/lib/data/webhook.dart`](../mobile/lib/data/webhook.dart), and `mobile/test/webhook_test.dart` writes it to the fixtures that [`format.test.ts`](../app/worker/apps/relay/webhooks/format.test.ts) and the example receiver's test read.

## Rules for a new message

- A new kind is off for each webhook until its owner ticks it. Notes always go.
- The published schema, `site/public/webhooks/v1.schema.json`, accepts fields it does not list, and gives a list that can grow, such as the health `type`, as text with examples: mark such a list `.meta(GROWS)` in `format.ts`. Run `npm run relay:api-doc` in `app/` after a format change.
- Until the public release, version 1 can change in any way, and the website says so. After it, version 1 only gets additions, and a change that breaks a receiver raises `version`.

Webhook versions, an *Upgrade* button, end dates for old versions and a changelog wait until just before the public release, as the `webhook-data-kinds` plan decided. Then a webhook on an ended version pauses, and what waits goes after its owner upgrades.

Up: [the wiki](README.md). See also [person spaces: webhooks](relay-spaces.md#webhooks) and [the Relay Everything website](relay-website.md).
