# Design: Share to Relay Everything

## Context

See [proposal.md](proposal.md) for why. This change applies after `apple-shortcuts-and-attachments` ships, and uses what it adds:

- **Files on notes.** Store schema 5 has an `attachments` table; a note's `notes` body carries `attachments: [{id, name, type, size}]`, and each file has its own outbox row, route `attachment`, sent after its note through `RelayApi.upload`. The server's `POST attachments` stores a file once per id (`added: false` on a resend). `RelayController.keepNote(text, files:, pin:)` checks the 10-file and 25 MB limits (`checkFiles` in `lib/data/attachments.dart`); `pin: false` keeps no place.
- **An inbox the app drains.** `RelayController.load` drains `shortcuts-inbox/`. That folder is in the app's own sandbox, so a share extension, a second process with its own sandbox, cannot write to it.

Today, too: the device key sits in the Keychain through `flutter_secure_storage` (`KeyVault`, `data/connection.dart`) in the app's default access group. It has two forms, `rek_…` as `Authorization: Bearer`, or the older Access pair. Settings live in the app's SQLite store. The server keeps a note once per `(device_id, client_id)`. `RelayChannels` in `ios/Runner/RelayBackground.swift` holds the `relay/files` method channel. iOS target 15.0, bundle ID `com.matthewwong525.relayApp`, automatic signing with the Admin App Store Connect key in `fastlane/Fastfile`.

## Goals / Non-Goals

**Goals:** an iOS share extension and an Android share target that make one note with text and files; no network call while sending is off; an immediate send from the card while sending is on; one stored copy whatever sends it.

**Non-goals:** a place on shared notes; a Flutter engine inside the iOS extension; background `URLSession` uploads that outlive the card; a new note kind; server changes.

## Decisions

### 1. iOS: a native Swift share extension, no Flutter inside

New target `ShareExtension` (`com.matthewwong525.relayApp.share`), iOS 15, embedded in Runner. Its principal class `ShareViewController` hosts a SwiftUI card. A Flutter engine in an extension is heavy against the extension's memory limit (about 120 MB) and slow to start; the card is small, so it is Swift.

`NSExtensionActivationRule` (a dictionary, no predicate): `SupportsText`, `SupportsWebURLWithMaxCount 1`, and `SupportsImageWithMaxCount`, `SupportsMovieWithMaxCount`, `SupportsFileWithMaxCount` and `SupportsAttachmentsWithMaxCount` at 20 each. The extension still applies the limits itself, so it can name what it leaves out. A count of 20, not 10, lets 12 photos open the card and say 2 were left out.

`SharedItems.swift` turns `NSExtensionItem`s into a draft: `text`, a link (a web URL, with the item's `attributedTitle` or `attributedContentText` as its title), and `files` (a file URL, or a `loadFileRepresentation`, copied at once by URL into the inbox's `.tmp-<clientId>/` in the App Group, because the system deletes its copy; a file over 25 MB is named, never copied). `ShareNote.swift` holds the rules and the note body, with no UI, so `RunnerTests` builds it too. Order: your words, then shared text, then the link's title and address.

*Alternative:* open the main app from the extension. Rejected by the person's choice: a share extension has no supported way to open its app.

### 2. One App Group, one Keychain group

`group.com.matthewwong525.relayApp` is added to both targets' entitlements. The App Group is also the Keychain access group, so no `keychain-access-groups` entry and no team prefix are needed at run time.

- **The key.** On iPhone, `KeyVault` writes with `IOSOptions(groupId: group.com.matthewwong525.relayApp, accountName: relay.shared)`. The service name differs from the old items', because a Keychain query with no group matches every group: a delete of an old item must never match a new one. `upgrade()`, on `load`, moves a key found only in the old group: it writes the shared items (the server last), reads them back whole, then deletes the old items. Whole shared items found at the next open delete what is left of the old. `forget` deletes both. A build with no App Group (`PlatformException`) keeps the app's own group. Android is unchanged: it has one home, so it never moves anything.
- **Settings the card needs.** The app writes `{sending}` to the App Group's `UserDefaults` (`suiteName: group…`) on `load` and on each `_saveSettings`, `connect`, `signIn`, `setServer` and `disconnect`, through a new `setShareSettings` method on `relay/files` (`ShareGroup.setSending` in `lib/share/inbox.dart`). It is true only while sending is on and a key is kept. The server comes from the Keychain with the key, so it has one home. The key itself never goes in `UserDefaults`. The extension sends only when `sending` is true **and** a key is in the shared Keychain group; an app version that never wrote the value reads as off.

*Alternative:* share the SQLite store with the extension. Rejected: two processes writing one drift file across sandboxes, and the extension would need the store's schema in Swift.

### 3. The inbox in the App Group

The extension writes `share-inbox/<clientId>/` in the group container: `note.json` and the copied files. It writes into `share-inbox/.tmp-<clientId>/` and renames when done, so the app never reads half a share.

```json
{"v": 1, "clientId": "…", "text": "…", "createdAt": 1762500000000,
 "files": [{"id": "…", "name": "IMG_2041.jpg", "type": "image/jpeg", "size": 2202009, "file": "IMG_2041.jpg"}],
 "sentNote": false, "sentFiles": []}
```

`lib/share/inbox.dart` drains it on `load`, on resume (`RelayController.resume()`, before `sync`), and in the hourly background round (`backgroundRound`, before the points). For each entry: take it by a rename to `.taking-<clientId>-<ms>`, the time of the take in the name because a rename keeps the folder's own modified time (one taken over 10 minutes ago is renamed and taken again), move the files into `attachments/` with the ids the card gave them (`keepFile` in `lib/data/attachments.dart`), add the note with no pin (`Store.addSharedNote`), mark it sent if `sentNote`, queue the note unless sent and each file not in `sentFiles` (only while sending is on), then delete the folder. The drain gets the App Group path from a new `appGroupPath` method on `relay/files`. A malformed entry is moved to `share-inbox/.bad/` and kept, not dropped, so a bug never loses a share. A `.tmp-` folder older than a day, left by a card the system closed, is deleted.

### 4. Sending from the iOS card

`ShareSender.swift` reads the server and key, then posts the note body to `/apps/relay/api/notes`, the same JSON the outbox sends (`clientId`, `text`, `createdAt`, `attachments`), then each file to `/apps/relay/api/attachments` with the same headers as `RelayApi.upload`. After each success it rewrites `note.json` (`sentNote`, `sentFiles`). One deadline for all of it: 20 seconds from *Save*. At the deadline, on a network error, or on a refused key, it stops and the card says *Kept. It sends when you open Relay Everything.* The inbox entry is renamed into place **before** the first send, so a killed extension still leaves the note for the app.

The body builder is the one place the Swift code copies Dart. A fixture, `mobile/test/fixtures/shared-note.json`, pins it: a Dart test checks that `LocalNote.toJson` with files equals it, and a `RunnerTests` test checks the Swift builder against the same file.

Double sending is safe: the server keeps a note once per client id and a file once per id, so the app's later send of anything the card is unsure of stores nothing new.

### 5. Android: a see-through `ShareActivity` running Dart

`ShareActivity` extends `FlutterActivity` with a see-through theme, `excludeFromRecents`, `taskAffinity` of its own, and intent filters for `SEND` (`text/plain`, `image/*`, `*/*`) and `SEND_MULTIPLE` (`image/*`, `*/*`). It overrides `getDartEntrypointFunctionName` to `shareMain`. Before Dart starts, Kotlin copies each `content://` stream into `cacheDir/shared/` (the read grant ends with the activity) and reads `EXTRA_TEXT` and `EXTRA_SUBJECT`; Dart asks for them on a `relay/share` channel.

`lib/share/share_main.dart` builds a `RelayController` as `main.dart` does, with no voice parts, loads it with `watch: false` (the app's own engine keeps location history), and shows `ShareCard` (`lib/share/share_card.dart`), the same card as iOS. *Save* (`saveShare`) calls `keepNote(text, files: …, pin: false)`, waits for `settled()` up to 20 seconds, then calls `SystemNavigator.pop()`, which finishes the activity and returns to the sharing app. The note is in the app's store at once, so no inbox is needed on Android.

`lib/share/draft.dart` holds the rules both cards share in Dart: words then text then link; files past 10 or over 25 MB left out with a reason. The iOS card mirrors them in Swift; the shared test table in `test/share/share_test.dart` and its Swift twin in `RunnerTests.swift` check the same six cases as the proposal's table.

### 6. No place on a shared note

`keepNote(pin: false)`, which Shortcuts already uses, skips `_pinThenSync` even with *Pin notes* on. The iOS drain stores no pin either.

## UX

### Use-case brief

You, in another app, see something worth keeping: a page, a photo, a receipt PDF. You want it in Relay Everything without leaving. Done is the card closing and you back where you were; the note is in your timeline and, with sending on, your space. Common case: a link with no words. Edge cases: sending off, no signal, too many or too big files, no key.

### Flow

- Any app → *Share* → *Relay Everything* → the card → (add words) → *Save* → *Sending…* → *Sent* → back in the app.
- Sending off: *Save* → *Kept on this phone.* → back in the app.
- No signal or slow file: *Save* → *Sending…* → *Kept. It sends when you open Relay Everything.* → back in the app.

### Hierarchy

- **Card top bar:** *Cancel* quiet on the left, *Relay Everything* as the title, *Save* the one primary action on the right.
- **Body:** what you share first (link title and address, a few lines of text, or thumbnails and file chips with sizes), then the *Add words* field, keyboard not raised at once so the item stays in view.
- **Foot line:** one muted line that says where it goes: *Sending is on: this goes to your space.* or *Kept on this phone. Sending is off.* A left-out item is one line above it, in the danger colour.
- **After *Save*:** the buttons lock; the foot line becomes *Sending…*, then *Sent*, for a moment before the card closes.

```screen
<div class="card col gap phone">
  <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>Relay Everything</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
  <div class="row gap"><span class="tag-outline">IMG_1.jpg</span><span class="tag-outline">IMG_2.jpg</span><span class="tag-outline">+ 8 more</span></div>
  <div class="field"><span class="muted">Add words</span></div>
  <span class="danger">2 photos left out: a note holds up to 10 files.</span>
  <span class="muted">Sending is on: this goes to your space.</span>
</div>
```

```screen
<div class="card col gap phone">
  <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>Relay Everything</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
  <div class="field col gap"><span>Ten rules for slow travel</span><span class="muted">example.com/slow-travel</span></div>
  <div class="field"><span>read on the train</span></div>
  <span class="muted">Kept. It sends when you open Relay Everything.</span>
</div>
```

## Risks / Trade-offs

- [Automatic signing may not register the extension's App ID, the App Group or the Keychain group by itself] → the first build task checks it in the TestFlight build; if it fails, register them once in the Apple developer site with the person's OK, then rebuild.
- [Moving the key to a new Keychain group could lose it] → the move writes the new item before deleting the old, reads the new one back, and a test with a fake storage covers a crash between the two steps.
- [The Swift note body drifts from Dart] → the shared fixture fails one of the two tests.
- [Two engines on Android write one SQLite file] → the same WAL and busy timeout the Shortcuts change set; the server's `ON CONFLICT` keeps one copy.
- [A large file read into the extension's memory] → files are copied and uploaded from disk (`URLSession.upload(fromFile:)`), never held whole.
- [The card sends with sending on, so a share leaves the phone in about a second] → that is the person's choice; the foot line says so before *Save*.

## Migration Plan

Phone-only. The first open of the new app moves the key to the shared Keychain group and writes the sending flag for the card; until then the card reads sending as off and only keeps notes. No server or database change.

## Open Questions

None.
