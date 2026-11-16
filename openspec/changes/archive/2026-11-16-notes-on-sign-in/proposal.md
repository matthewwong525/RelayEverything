# Your notes come in as soon as you sign in

**Status:** ready-to-ship
**Branch:** fix-mac-notes-sync-sign-in
**Open questions:** none

## Why

You signed in on the Mac app and your notes from your phone and the web did not show. Signing in sends the Mac's own notes, but it does not get your notes from the server. They show only after about 5 minutes, or after you click another app and then come back to the window. The iPhone and Android apps use the same sign-in, so a new phone can wait in the same way.

## What Changes

- **What you get: your notes show right after you sign in.** When you sign in, or turn sending to Relay Everything back on, the app sends its own notes first and then gets your notes from your other phones, the browser, email and your AI apps. You do not wait 5 minutes, and you do not click away and back.
  ```mermaid
  sequenceDiagram
    participant You
    participant Mac as Mac app
    participant Server as Relay Everything
    You->>Mac: Sign in
    Mac->>Server: Send this Mac's notes
    Mac->>Server: Get your other notes
    Server-->>Mac: Your notes
    Mac-->>You: All your notes show
  ```
- **What changes in how you work.** Nothing. Sign in from Settings as before.
  ```text
  Before: sign in → this Mac's notes only
          → wait 5 min, or click away and back
  After:  sign in → this Mac's notes
          → then all your notes, in seconds
  ```
- **What stays.** Your own webhook gets no pull, as before: the app gets notes only from Relay Everything. With sending off, the app calls nothing.
  ```text
  To Relay Everything ... send, then get notes
  To your webhook ....... send only (as now)
  Sending off ........... nothing (as now)
  ```
- **The help pages say so.** *Connect a phone* and the Mac app part of *On a computer* say that your notes come in when you sign in.
  ```text
  site: Connect a phone, step 6
  site: On a computer › The Mac app
  ```

## What the build needs

- **Nothing.**

## Capabilities

### New Capabilities

### Modified Capabilities
- `relay-note-sync`: a signed-in device also gets its notes when sending to Relay Everything starts, such as right after sign-in.

## Impact

- `mobile/lib/controller.dart`: `startSending` asks for a pull with its round when the place is the server.
- `mobile/test/note_sync_test.dart`: a regression test for sign-in, then pull.
- `mobile/README.md` (Mac app *Sync* line), `site/src/content/docs/start/connect-a-phone.md`, `site/src/content/docs/app/on-a-computer.md`.
- No server, route or data change.
