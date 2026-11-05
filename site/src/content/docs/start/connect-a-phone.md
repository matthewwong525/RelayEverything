---
title: Connect a phone
description: Give a phone its own key, so it can send notes to your Relay server and read them back.
---

Each phone connects to your Relay server with its own key. The key also holds the server's address, so you type no address.

## Make the key

The owner of the Relay server makes one key for each phone, on the computer that holds the server's project:

```sh
node scripts/relay-device-key.mjs create --name "Android phone"
```

The key shows once: as a QR code in that terminal, and on a private page on that computer. It lasts one year. [Keys](../../api/keys/) tells more about keys.

## Connect

1. Open the Relay app. It shows **Connect Relay**.
2. Tap **Scan the QR code**, and point the camera at the key's QR code.
   Or tap **Or paste the key**, paste it, and tap **Connect**.
3. The app asks once for your location, so each typed note keeps where you were. Allow it, or turn it off later in [Settings](../../app/settings/).

When the phone connects, it shows your notes, newest first. Delete the key's private page when the phone is connected.

## Turn a phone off

- **On the phone:** open **Settings**, then tap **Disconnect this phone**. The key leaves the phone. Notes not sent yet stay on the phone. You need a new key to connect again.
- **From the server:** the owner runs `node scripts/relay-device-key.mjs revoke --name "Android phone"`. That key stops at once, and the other keys go on.

## Try a preview

A preview of a change to Relay has its own address and its own keys. Make its key with `--staging`, then in the app open **Settings**, tap **Server**, and enter the preview's address.

## Next

[Set up the Pebble webhook](../pebble-webhook/), so the ring's notes reach Relay.
