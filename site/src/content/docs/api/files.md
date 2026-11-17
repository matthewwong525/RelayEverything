---
title: Files
description: The routes that send a note's file to the Relay Everything server and open it again.
---

A note can hold up to 10 files, each up to 25 MB. The phone sends a note's files in two steps: first the note with its list of files in [`POST notes`](../reference/#store-a-typed-note), then each file's bytes. A note of files can have no words.

## Send a file

`POST /apps/relay/api/attachments` takes one file's raw bytes as the body, with a phone's [device key](../keys/). Send it after its note, as the note's list names the file:

```sh
curl https://<your-relay-server>/apps/relay/api/attachments \
  -H "Authorization: Bearer rek_…" \
  -H "X-Note-Client-Id: <the note's clientId>" \
  -H "X-Attachment-Id: <the file's id from the note's list>" \
  -H "Content-Type: application/pdf" \
  --data-binary @warranty.pdf
```

The server seals the file with your space's own key and keeps it in your own folder of the file store. It answers `{ "ok": true, "added": true }`. A file sent again answers `"added": false` and is kept once.

| Status | When |
|---|---|
| `400` | A header is missing, or is not an id. |
| `404` | The note is not one this device sent, or its list does not name this file. |
| `413` | The file is larger than 25 MB. |

## Place a file in the words

A note's `text` marks where each file shows, with a line of its own: `![warranty.pdf](attachment:<the file's id>)`. The phone writes the line when you add a file, and shows the file there. A file with no line shows after the words, and a recording the note started with shows first. Your AI and your webhooks read the line as normal text.

## Remove a file

[`PATCH notes`](../reference/#change-a-note) takes `removed`, up to 10 file ids, from the device that sent the note. The server deletes each file's row and its sealed bytes, skips an id the note does not have, and sends one `note.updated` with the files that stay. A file that `attachments` leaves out stays: only `removed` removes one.

```sh
curl -X PATCH https://<your-relay-server>/apps/relay/api/notes \
  -H "Authorization: Bearer rek_…" \
  -H "Content-Type: application/json" \
  -d '{"clientId":"<the note's clientId>","text":"Lease","editedAt":1763400000000,"removed":["<file id>"]}'
```

A `removed` from another device's note answers `400` with `not_own`. A removal sent again changes nothing.

## Open a file

`GET /apps/relay/api/attachment?id=<file id>` sends a file back, with its own `Content-Type`. A signed-in person calls it on the Relay Everything page, and a phone's [device key](../keys/) calls it when you tap a synced note's file in the app. A chat key or an API key can't. A picture opens in the page; any other file downloads with its own name.

Take the file's id from [`GET timeline`](../reference/#read-the-notes): each note lists its `attachments`, and a file with `"ready": true` has arrived.

| Status | When |
|---|---|
| `400` | The `id` is not a file's id. |
| `404` | No note in your space has this file, or it has not arrived yet. |
