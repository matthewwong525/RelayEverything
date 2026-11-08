# Design: the phone's account in Settings

## Context

Home today has three groups: the notes folders, *On this phone*, and *Connections* (*Sending*, *AI apps*, *Webhooks*). Sign-in starts from the *Send my notes* switch on the *Sending* page (`SendingPage` in `mobile/lib/screens/folder.dart`), which opens `ConnectScreen` through `choosePlace`. Sign-out is *Disconnect this phone* on the same page. The phone reads `GET connections` (names of AI apps and webhooks) only while it sends to a Relay Everything server.

## Goals / Non-Goals

**Goals:** one place for the account, as in iPhone Settings; sign in and sending as one step; Home shows only notes and phone data.

**Non-Goals:** the AI connector, the web page's *AI apps* and *Webhooks* parts, managing AI apps or webhooks on the phone, deleting the account from the phone.

## Decisions

### Account row and page

`SettingsScreen` gets an `_AccountRow` first, outside the titled groups, in its own card with `RelayMark`. Three states come from what the controller already knows: `connected && sending && place == server` → email and server host; `sending && place == webhook` → *My own webhook* and the webhook host; else → *Sign in to Relay Everything*. A tap on the signed-out row runs `choosePlace`; otherwise it opens `AccountPage` (new `mobile/lib/screens/account.dart`), built from today's `SendingPage` minus the *Send my notes* switch and *Where the phone sends*, plus the *AI apps* and *Webhooks* rows moved from `home.dart`'s `_connected`. *Disconnect this phone* becomes *Sign out* and keeps its confirm dialog and behavior. `SendingPage` and the `Connections` section go.

Alternative: keep a *Send my notes* switch on the Account page as a pause. Rejected by the person's pick (one step): two switches that look alike was the problem.

### The email

`GET connections` adds `email` from `caller.email`: a phone key's own person, the same value `GET account` gives a session. The route stays names-only for everything else. `Connections.fromJson` reads `email` as optional, so a server not yet updated shows the server host alone.

### Sign-in screen

`ConnectScreen` keeps its job and its returns (`SendPlace`). Its segmented *Relay Everything / My own webhook* choice becomes one screen titled *Sign in*: *Sign in to connect* is the primary button; *Scan a key*, *Use another server* and *Send to my own webhook instead* are quiet buttons below. The webhook part opens in place, as today's webhook segment does. A kept key still shows *This phone has a key for …* with one tap to send there.

### Sending with no switch

`choosePlace` already asks about earlier notes and calls `startSending`. The only caller left is the sign-in path (Account row, folder pages' *Sign in*). *Stop sending* in webhook mode calls the existing sending-off, which keeps the webhook in the vault.

## UX

### Use-case brief

The person owns one phone and maybe a Relay Everything account. Jobs: sign in once at setup; later check what is connected; rarely sign out. Done looks like Settings showing their email. Context: iPhone, one hand, mostly offline at first. Common case: the shared server. Edge cases: a self-hosted server, a key from a QR code, their own webhook with no account. Mirrors iPhone Settings' Apple Account row.

### Flow

Home → gear → Settings → *Sign in to Relay Everything* → sign in in the browser → earlier-notes question → back in Settings showing the email. Edges branch from the sign-in screen: *Scan a key*, *Use another server*, *Send to my own webhook instead*. Later: Settings → Account row → Account page → *AI apps* / *Webhooks* open the web page; *Sign out* asks, then signs out.

### Hierarchy

- Settings: the Account row is the first and largest row; the rest is as today.
- Sign-in screen: *Sign in to connect* is the one primary button; the other ways are quiet.
- Account page: no primary button; *Sign out* is the only red row, last.
- Home: *New note* stays the one bright control.

### Review

[review.html](review.html). What Changes items 1, 2 and 4 sketch Home, Settings (signed in and signed out) and the Account page; item 3 draws the sign-in flow.

### Components

Existing: `Group`, `ListTile`, `RelayMark`, `BackTo`, `SliverAppBar.large`, `CupertinoIcons`, the `_FolderRow` look from Home for the *AI apps* and *Webhooks* rows (moved to a shared spot), and the existing confirm dialog. New: `AccountPage` and `_AccountRow`, because no screen held the account before.

## Risks / Trade-offs

- An existing phone with a key and sending off now reads as signed out. The kept key makes signing in one tap, so nothing is lost.
- The iPhone tour's Settings flow taps Home's *Sending*; it must change in the same change, or the check fails.
- Removing the pause switch means a person who wants to stop for a while signs out and later signs in again, which makes a new key. Accepted by the person's pick.
