---
title: Recordings
description: The route that plays a ring note's recording.
---

`GET /apps/relay/api/audio?id=<note id>` sends a ring note's recording, as `audio/mp4`. A phone with its [device key](../keys/), or a signed-in person, can call it.

Take the note's id from [`GET timeline`](../reference/#read-the-notes): a note with `"audio": true` has a recording.

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
| `404` | No note has that id, or the note has no recording. The body is `{ "error": "Not found" }`. |
