---
title: Connect a phone
description: Turn on sending, and give a phone its own key, so it can send notes to your Relay Everything server.
---

The Relay Everything app keeps your notes on the phone, with no key. To send them to your Relay Everything server, you turn on sending and connect the phone with its own key. The key also holds the server's address, so you type no address.

## Make the key

You make one key for each phone, on the computer where you [made your Relay Everything server](../run-your-own/):

```sh
node scripts/relay-device-key.mjs create --name "Android phone"
```

The key shows once: as a QR code in that terminal, and on a private page on that computer. It lasts one year. [Keys](../../api/keys/) tells more about keys.

## Connect

1. Open the Relay Everything app, then open **Settings** from the gear at the top.
2. Turn on **Send to Relay Everything**. The app shows **Connect Relay Everything**.
3. Tap **Scan the QR code**, and point the camera at the key's QR code.
   Or tap **Or paste the key**, paste it, and tap **Connect**.
4. If you wrote notes before, the app asks **Send your earlier notes too?** Tap **Send them** to send them, or **Only new notes** to keep them only on the phone. The app asks again each time you turn sending on.

To connect, the phone checks its key with the server, and reads no data. Then your notes go to your server. The key only adds data, so the phone shows only its own notes: ring notes and recordings are on your Relay Everything page, and **Open your Relay Everything page** opens it. Delete the key's private page when the phone is connected.

## Stop sending

Turn off **Send to Relay Everything** in **Settings**, and tap **Stop sending**. New notes stay on the phone. Notes already on your server stay there. Health and location stop, and what of them did not go yet is deleted. The key stays on the phone, so you can turn sending on again with no new key.

## Turn a phone off

- **On the phone:** open **Settings**, then tap **Disconnect this phone**. The key leaves the phone, and sending turns off. Your notes stay on the phone. You need a new key to send again.
- **From the server:** the owner runs `node scripts/relay-device-key.mjs revoke --name "Android phone"`. That key stops at once, and the other keys go on.

## Try a preview

A preview of a change to Relay Everything's own server has its own address and its own keys. Make its key with `--staging`, then in the app open **Settings**, tap **Server**, and enter the preview's address.

## Next

[Set up the Pebble webhook](../pebble-webhook/), so the ring's notes reach Relay Everything.
