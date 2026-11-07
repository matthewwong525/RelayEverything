# Share to Relay Everything from any app

**Status:** ready-to-ship
**Branch:** chosen-cat
**Open questions:** none

## Why

To keep a link, a photo, a file or some text today, you must open Relay Everything and type it again. Every app on the phone has a *Share* button. With Relay Everything in that list, one tap keeps the item as a note, and you stay in the app you were in.

## What Changes

- **Relay Everything is in the share list.** In Safari, Photos, Files, Mail or any other app, tap *Share*, then *Relay Everything*. On iPhone and on Android.
  ```mermaid
  flowchart LR
    A["Any app"] --> B["Share"]
    B --> C["Relay Everything"]
    C --> D["The share card"]
  ```
- **A small card opens over the app.** It shows what you share: the page's title and link, the text, or the photos and files. You can add your own words. Tap *Save*, and the card closes. You are back where you were.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>Relay Everything</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
    <div class="field col gap"><span>Ten rules for slow travel</span><span class="muted">example.com/slow-travel</span></div>
    <div class="field"><span class="muted">Add words</span></div>
    <span class="muted">Sending is on: this goes to your space.</span>
  </div>
  ```
  This sketch stands in for a picture: the phone app does not run in the plan's preview.
- **Each kind of item becomes part of one note.** Words and links go in the note's text. Photos and files go on the note as files, with the same limits as *New note*: up to 10 files, each up to 25 MB. A file that is too big is left out, and the card says so. The note's time is the time you share. A shared note has no place, even with *Pin notes* on.
  | You share | The note gets |
  | --- | --- |
  | A web page | Its title and link as text, and your words |
  | Text | The text, and your words |
  | Photos | The photos as files, and your words |
  | A PDF or other file | The file, and your words |
  | 12 photos | The first 10; the card says 2 were left out |
  | A 40 MB video | Your words only; the card says the video is too big |
- **With sending off, the note stays on the phone.** The card makes no network call. The note is in your timeline the next time you open Relay Everything. *Send them* sends it later, as with any other note.
  ```screen
  <div class="card col gap phone">
    <div class="row gap"><button class="btn-ghost">Cancel</button><span class="grow"></span><h3>Relay Everything</h3><span class="grow"></span><button class="btn-primary">Save</button></div>
    <div class="row gap"><span class="tag-outline">IMG_2041.jpg · 2.1 MB</span><span class="tag-outline">IMG_2042.jpg · 1.8 MB</span></div>
    <div class="field"><span>Paint colours for the hall</span></div>
    <span class="muted">Kept on this phone. Sending is off.</span>
  </div>
  ```
  This sketch stands in for a picture: the phone app does not run in the plan's preview.
- **With sending on, the card sends at once.** After *Save*, the card shows *Sending…*, then *Sent*, and closes. Your webhooks get the note as they get a typed note. If the phone has no signal, or a big file does not finish in about 20 seconds, the card closes with *Kept. It sends when you open Relay Everything.* The app sends the rest on its next open or at the hourly round. A note is never stored twice.
  ```mermaid
  sequenceDiagram
    participant C as Share card
    participant P as Phone
    participant S as Your space
    C->>P: Keep the note and files
    C->>S: Send the note, then each file
    S-->>C: Stored
    Note over C: Sent, card closes
    P->>S: On next open: anything not sent
  ```
- **On iPhone the card is Relay Everything's own share extension.** It uses the phone's own device key, so it needs no new key. A phone with no key, or with the key turned off, keeps the note and sends nothing.
- **On Android the card is a small Relay Everything window.** It opens over the app you share from, and *Save* takes you back there.
- **The website says how.** A new *Share from any app* page, and the notes and privacy pages name it.

Non-goals: Apple Shortcuts (the plan *Add notes and files from Apple Shortcuts*); a place on shared notes; sharing into an existing note; sharing out of Relay Everything; a Mac or iPad share; a new note kind such as *Shared*.

## What the build needs

- **App Store Connect key for TestFlight builds**: Ready, in `.env` and the repository's secrets. The build adds a second app part (the share extension) and a shared folder, which the key signs on its own.
- **Your iPhone with TestFlight**: Ready, you have the app. After the build you share a page from Safari and a photo, and see both on your page.

## Capabilities

### New Capabilities

- `relay-share`: the share button on iPhone and Android: what it takes, the card, keeping on the phone, sending at once while sending is on, and the app picking up shared notes.

### Modified Capabilities

None.

## Impact

- `mobile/ios/ShareExtension/` (new target): `ShareViewController.swift` (SwiftUI card), `SharedItems.swift` (items to a draft), `ShareInbox.swift` (writes to the App Group), `ShareSender.swift` (posts `notes` and `attachments` with the device key), `ShareNote.swift` (the rules and the note body, also built into `RunnerTests`), `Info.plist` (activation rule), `ShareExtension.entitlements`.
- `mobile/ios/Runner.xcodeproj`: the extension target, embedded in Runner. `Runner.entitlements`: App Group `group.com.matthewwong525.relayApp`, which is also the shared Keychain group. `RunnerTests/`: a test of the Swift note body against a shared fixture.
- `mobile/android/app/src/main/`: `AndroidManifest.xml` (a `ShareActivity` with `SEND` and `SEND_MULTIPLE` filters), `kotlin/…/ShareActivity.kt` (copies shared items, runs the Dart entry point `shareMain`), a see-through theme.
- `mobile/lib/`: new `share/` folder (`inbox.dart` drains the iPhone inbox, `share_main.dart` the Android entry point, `share_card.dart` the Android card, `draft.dart` items to a note); `data/connection.dart` (the key moves to the shared Keychain group); `controller.dart` (load, resume and the hourly round drain the inbox; the sending flag mirrored to the App Group; the existing `keepNote(pin: false)` keeps no place); `data/attachments.dart` (`keepFile`, shared by the paperclip, Shortcuts and the drain); `data/store.dart` (`addSharedNote`); `sync/background.dart`, `sync/wake.dart`, `shortcuts/entry.dart`; `main.dart`. In Swift, `ios/Runner/RelayBackground.swift` answers `appGroupPath` and `setShareSettings` on `relay/files`. No new package: the App Group values go through the existing `relay/files` channel.
- `mobile/test/`: drain, draft, Android card, fixture.
- `.github/workflows/mobile-device-check.yml`: runs `RunnerTests` on the Mac. `mobile/device-check/flows/share-link.yaml`: shares a Safari page with sending off.
- `site/src/content/docs/app/`: new `share.md`, `your-notes.md`, `site/src/content/docs/privacy.md`. `scripts/product-name.test.mjs` lists the extension's `Info.plist` and the new page.
- Order: this build starts only after `apple-shortcuts-and-attachments` ships; task 1.1 checks it.
- No server change: a shared note uses the `notes` and `attachments` routes as they are after *Add notes and files from Apple Shortcuts*.
- Overlap: `phone-health-places-ring` and `apple-shortcuts-and-attachments` also edit the Swift channels, `Runner.xcodeproj`, `Info.plist` and `controller.dart`; this change applies after both and rebases.

## Decision log

**2026-11-07** — Asked what happens when you tap Relay Everything in the iPhone share list → chose "Small sheet, stay put (Recommended)": a card over the other app, with your words and *Save*.
**2026-11-07** — Asked when a note shared on the iPhone goes to your space, with sending on → chose "At once, from the card": the extension sends it itself with the phone's key, and the app sends what it could not.
**2026-11-07** — Asked what the share does on Android → chose "Same card, then back (Recommended)": a small window over the other app; *Save* returns you there and sends at once.
**2026-11-07** — Assumed: a shared note has no place, because a share extension may not ask for the location, and a place found later in the app would be the wrong place.
**2026-11-07** — Assumed: a link becomes the note's text (title, then link), not a file, because the timeline, search and webhooks read text, and a link is short.
**2026-11-07** — Assumed: a file over 25 MB or past the tenth is left out with a line on the card, not a refused *Save*, because the rest of the share still has value.
**2026-11-07** — Assumed: a shared note keeps the kind *typed*, because a new kind changes the server, the page filter and the webhook format for a label only.
**2026-11-07** — Assumed: the card gives up sending after about 20 seconds, because iOS closes an extension soon after it finishes, and the app sends the rest on its next open.
**2026-11-07** — Assumed: this change applies after *Add notes and files from Apple Shortcuts* ships, because it uses that change's files on notes, and a second copy of file handling would go stale.
**2026-11-07** — Assumed: the App Group itself is the Keychain group, with the service name `relay.shared`, not `$(AppIdentifierPrefix)…shared`, because it needs no team prefix at run time and a delete of an old item can not match a new one.
**2026-11-07** — Assumed: the card's settings in the App Group are `{sending}` only, not `{sending, server, device}`, because the server comes from the Keychain with the key, so it has one home.
**2026-11-07** — Assumed: `appGroupPath` and `setShareSettings` go in `RelayChannels` (`ios/Runner/RelayBackground.swift`), where `relay/files` lives since the health and places change, not in `AppDelegate.swift`.
**2026-11-07** — Assumed: the plan's `addNote(place: false)` is the shipped `keepNote(pin: false)`, which Shortcuts already uses, so no second flag exists.
**2026-11-07** — Assumed: the iPhone activation counts are 20 for images, movies, files and attachments, not 10, so 12 photos open the card and it can say 2 were left out.
**2026-11-07** — Assumed: the left-out lines reuse the app's own `checkFiles` words (*A note holds up to 10 files. 2 files were not added.*), so the paperclip, Shortcuts and the share card say the same thing.
**2026-11-07** — Assumed: the drain moves each file with the id the card gave it, through the paperclip's `keepFile`, so a file the card sent is the same file on the server; it drains on load, on each return to the app, and in the hourly round.
**2026-11-07** — Assumed: the Android share window loads the app with `watch: false`, so it starts no second location history beside the app's own.
**2026-11-07** — Assumed: the Swift tests run after the device check's video and Claude's turn, because the test host reinstalls the app on the simulator.
- **2026-11-07** — Check: `.github/workflows/mobile-device-check.yml` gets a new *Swift tests* step and loosens nothing, because the share card's Swift rules must be checked against the Dart ones on the Mac; a failure there makes the check broken.
**2026-11-07** — Assumed: the hand check on Matthew's iPhone (share a Safari page and a photo, sending on, then off) runs after the publish, not as a build task, because TestFlight builds come only from `main`.
**2026-11-07** — Built the share card on iPhone (a Swift share extension) and Android (a see-through window), the inbox drain, and the website page; a second look found 3 bugs (iPhone files sent from a moved folder, Android list not reloaded on return, a double take of one share), all fixed. The Swift code is compiled first by CI on the Mac.
**2026-11-07** — The first iPhone build failed: the build key registered the share card's app ID but gave neither ID the App Group. Matthew said yes, and the assistant registered `group.com.matthewwong525.relayApp` on the Apple developer site and turned it on for `com.matthewwong525.relayApp` and `com.matthewwong525.relayApp.share`; the wiki's *Phone builds* section now says how.
**2026-11-07** — The iPhone device check (run 42387327750) said works: the card opened over Safari with the title, link and *Kept on this phone. Sending is off.*, *Save* closed it, and the note showed in the timeline; the Swift tests passed. The photo share was not checked (no photo on the simulator). The Maestro flow `share-link.yaml` fails on this iOS, whose Safari keeps *Share* in its *…* menu; Claude's check covered the same steps by hand.
