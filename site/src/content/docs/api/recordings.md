---
title: Recordings
description: The route that plays an older recorded note's recording.
---

`GET /apps/relay/api/audio?id=<note id>` sends an older recorded note's recording, as `audio/mp4`. A signed-in person calls it on the Relay Everything page, and a phone's [device key](../keys/) calls it to play a synced older recorded note in the app. A chat key or an API key can't.

Each recording is in its person's own folder in the file store, sealed with a key kept in their space, so it opens only through this route for that person. Take the note's id from [`GET timeline`](../reference/#read-the-notes): a note with `"audio": true` has a recording.

## Part of a file

The route answers one byte range, as some players, such as Safari's, ask for one before they play:

| Request | Answer |
|---|---|
| No `Range` header | `200` with the whole file |
| `Range: bytes=0-1023` | `206` with those bytes and a `Content-Range` header |
| A range past the file's end | `416` with `Content-Range: bytes */<size>` |
| Several ranges | `200` with the whole file |

## Errors

| Status | When |
|---|---|
| `400` | The `id` is not a note's id. |
| `404` | No note in your space has that id, or the note has no recording. The body is `{ "error": "Not found" }`. |
