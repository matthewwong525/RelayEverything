# A Relay Everything app for your Mac: your notes in the computer page's three-part window, kept on the Mac and working offline

**Status:** ready-to-ship
**Branch:** build-mac-app
**Open questions:** none

## Why

On a computer, you use Relay Everything today only in a browser tab. The tab needs the internet, keeps no notes, and is easy to lose among other tabs. A Mac app gives you Relay Everything in your Dock, with your notes on the Mac, so you can read and write them with no connection.

## What Changes

- **A Relay Everything app for the Mac.** It opens in its own window from the Dock, with the computer page's three parts: the left bar, your notes by day, and the open note. A narrow window shows two parts, then the phone layout, as the page does. The left bar has *Notes*, then *Connect your AI* and *Email notes*, and *Settings* at the bottom.
  ```picture
  Closest real result, the computer page today: pictures/notes-computer.png
  ```
  ```screen
  <div class="card row gap">
    <div class="col gap"><b>Notes</b><span class="tag">128</span><span class="muted">Other connections</span><span>Connect your AI</span><span>Email notes</span><span class="sep"></span><span>Settings</span></div>
    <div class="col gap grow"><h3>Notes</h3><span class="muted">Today</span><div class="card">Call the ring maker</div><div class="card">Ideas for the trip</div><span class="muted">Yesterday</span><div class="card">Shopping list</div></div>
    <div class="col gap grow"><h3>Call the ring maker</h3><span class="bar"></span><span class="bar"></span><div class="row gap"><span class="grow"></span><span class="tag-outline">Saved on this Mac</span></div></div>
  </div>
  ```

- **Your notes stay on the Mac and work offline.** As on the phone, the app keeps every note on the Mac. Signed out, it makes no network call, and your notes stay only on this Mac. When you sign in, your notes go to Relay Everything, and notes from your phones and the web come to the Mac. A note you write with no connection waits and goes when the Mac is online again.
  ```mermaid
  flowchart TB
    K[Kept on the Mac] -->|online| R[Relay Everything]
    R --> P[Phones, web]
    P --> R --> K
  ```

- **Sign in as on the phone.** In *Settings*, *Sign in to Relay Everything* opens Apple's sign-in sheet. You sign in with an email code, Apple or Google, and click *Connect*. The Mac gets its own key, which you can sign out on your phone or on your Relay Everything page, like a phone. *Don't want an account? Use your own webhook* works too.

- **Made for a keyboard and mouse.** The Mac menu bar has *New Note* (⌘N), *Find* (⌘F), *Bold* (⌘B), *Italic* (⌘I) and *Settings* (⌘,). You drop files from Finder onto an open note. Links open in your browser, and a file on a note opens in its Mac app.

- **Only what a Mac can do.** The Mac sends no health, places, calendar or photos: it has no Apple Health, and your phone already sends where you go. A voice note from your phone shows its words on the Mac, because the recording stays on the phone. The Mac records no voice notes in this first version. *Webhooks*, *Saved chats* and *Delete my account* open your Relay Everything page in the browser, as they do on the phone.

- **A download on the website.** The website's *Install* page gets a *Mac* part with a *Download for Mac* link. The app is signed by Apple's Developer ID and checked by Apple, so it opens with no warning. It runs on Apple silicon and Intel Macs. Each release puts the Mac app on its GitHub release, beside the Android app; each new build on `main` puts one on its beta release, for you to try first.

**Non-goals:** the Mac App Store; updates that install by themselves (you download a new version from the website); recording voice notes on the Mac; any change to what a key may read on the server; Windows and Linux.

## What the build needs

- **App Store Connect key and team id**: Ready. `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8` and `APPLE_TEAM_ID` are in `.env` and in the GitHub secrets. Apple's check of the Mac app (notarization) uses the same key.
- **A Developer ID certificate**: Ready to try. The build first asks Apple for it with the App Store Connect key, as the iPhone certificate script does, and saves it as `MACOS_DEVID_CERT_P12` and `MACOS_DEVID_CERT_PASSWORD`. If Apple answers that only the Account Holder can make one, the build stops and asks you to make it once here: https://developer.apple.com/account/resources/certificates/add

## Capabilities

### New Capabilities

- `relay-mac-app`: the Relay Everything Mac app: its window and layout, notes kept on the Mac, sign-in and its key, what it leaves out, its menus and file drops, and its signed build and download.

### Modified Capabilities

None.

## Impact

- `mobile/`: a new `macos/` Flutter runner, a new entry `lib/main_mac.dart`, `RelayPlatform.mac`, the wide shell made to run on `RelayController` as well as `WebRelay`, a Mac file drop (`desktop_drop`), the Mac menu bar, and tests.
- CI: a Mac build job in `.github/workflows/` on each pull request that changes `mobile/` (unsigned, sends nothing); on `main` and a release, a signed, notarized `.dmg` on the GitHub release.
- `scripts/`: the signing-certificate script makes a Developer ID certificate too; a release attaches the `.dmg`.
- `site/`: the *Install* page and *On a computer* page; `mobile/README.md`.
- Server: no change. The Mac signs in through the phone's existing sign-in route and gets a key with the phone's reach.

## Decision log

- **2026-11-15** — Asked what kind of Mac app → chose a real Mac app you download and open from the Dock, not the browser page added to the Dock and not the iPhone app on a Mac.
- **2026-11-15** — Asked how to make it → chose a full native Flutter app that keeps notes on the Mac and works offline, not a Mac window around the web page.
- **2026-11-15** — Asked how to get it onto a Mac → chose a download from the website, signed with Developer ID and checked by Apple, not the Mac App Store and not an unsigned build.
- **2026-11-15** — Assumed: the Mac gets a key with the phone's reach through the phone's existing sign-in route, and the page-only parts (webhooks, API keys, saved chats, delete account) open the Relay Everything page in the browser, as the phone does, because that needs no server change and gives no key more reach. The explore question said the server would need a Mac key with page-level access; that can come in a later plan if you want those parts inside the app.
- **2026-11-15** — Assumed: the Mac app joins the phone app's notes code (`RelayController`, kept in a local database) with the computer page's wide layout, because both already share one `Relay` base, so the Mac gets offline notes and the page's three parts with little new code.
- **2026-11-15** — Assumed: the Mac sends no health, places, calendar or photos, and hides those folders, because the health, calendar and voice-to-text libraries have no Mac support, and the phone already sends places.
- **2026-11-15** — Assumed: no voice recording on the Mac in this plan, because the speech-to-text library (`whisper_cpp_flutter_plus`) has no Mac build; voice notes from a phone still play.
- **2026-11-15** — Assumed: the Mac shows in the phone list on the Account page under its Mac name, because its key has a phone's reach; a separate *Computers* heading can come later.
- **2026-11-15** — Assumed: no self-update in this plan, because a self-update library (Sparkle) adds its own signing and feed; Settings shows the version, and the website has the newest.
- **2026-11-15** — Assumed: the key is kept in the Mac's login keychain with no keychain sharing, because keychain sharing needs a Developer ID profile, and the Mac app has no extension to share with.
- **2026-11-15** — Assumed: the web guidance was not read for this plan, because the Mac app reuses the existing Flutter screens and no new web page is made.
- **2026-11-15** — Assumed (daily line-up note): the Mac build and its `.dmg` upload stay a separate job and a separate release step, and the README gets its own new section, because the app-store-listing change also edits the `v` release and `mobile/README.md`; whichever change lands second keeps the other's lines.
- **2026-11-15** — Assumed (daily line-up note): the Mac app gets no paste code of its own, because it uses the shared note editor, and the paste-keeps-formatting change fixes paste there for every platform.
- **2026-11-15** — Check: `.github/workflows/mobile-ci.yml` adds the `macos-branch`, `macos` and `macos-beta` jobs and makes the release job wait for `macos`, because the Mac app builds and ships beside the phone apps; no existing check is turned off or made weaker.
- **2026-11-15** — Check: `.github/workflows/mobile-macos.yml` is the new Mac build, because it signs, notarizes and staples the `.dmg`; on `main`, missing Mac secrets skip the file with a notice, as the iPhone build does, and a release still fails.
- **2026-11-15** — Check: `mobile/test/mac_imports_test.dart` reaches `lib/controller.dart` but does not read it, because the shared controller imports the phone's sources for the phone entry to pass in; the Mac passes none, and `controller_test.dart` keeps a Mac controller working with none.
- **2026-11-15** — Assumed: `mobile/macos/Runner/Release.entitlements`, the file the shipped app is signed with, holds only App Sandbox, network client and user-selected files; `DebugProfile.entitlements` also keeps Flutter's `cs.allow-jit` and `network.server`, because `flutter run -d macos` needs them, and no release uses that file.
- **2026-11-15** — Assumed: the minimum macOS is 12.0, Flutter's default now, not 11, because the plan asked for Flutter's default.
- **2026-11-15** — Assumed: the Mac has no voice parts at all (`voice: null`), because a phone recording never leaves the phone, so a Mac has no recording to play; a sound file on a note opens in the Mac's own player.
- **2026-11-15** — Assumed: `desktop_drop` 0.8 (Apache-2.0), not 0.9, because 0.9 needs a `cross_file` that `share_plus` 13 refuses.
- **2026-11-15** — Assumed (review): coming back to the Mac window asks the controller to pull (`pullNotes`, which sends what waits, then reads), in `WebShell`'s resume listener on the Mac only, because the controller's `sync` only sends; the browser keeps `sync`, which reads too. `mac_shell_test.dart` checks it.
- **2026-11-15** — Assumed (review): the spec, the proposal and the design now say a phone's voice note shows its words on the Mac, and the Mac records and plays none, because the build has no voice parts (`voice: null`) and a phone recording never leaves the phone. This replaces the earlier line that said voice notes from a phone still play.
- **2026-11-15** — Assumed (review): the *On a computer* page says the Mac shows only under **Phones**, because the server lists a key with a phone's reach there and not in *Connect your AI*.
- **2026-11-15** — Assumed (review): `pubspec.lock` keeps every earlier version and adds only `desktop_drop` 0.8.4 and its `universal_platform` 1.1.0, because the plan named no other upgrade; `record`, `file_picker`, `drift`, `url_launcher` and the rest stay as they were.
- **2026-11-15** — Assumed (review): the Mac keeps *Find in Note* in the note's ⋯ menu, and only the browser hides it, because the browser has its own find and the Mac's ⌘F goes to the notes search.
- **2026-11-15** — Assumed (review): on the Mac, the signed-out lines in the notes list and Settings, the Account page's *This Mac*, its *Sign out?* question and the webhook's *Stop sending* line and question say *this Mac*, through `Relay.device`; the Mac's *Stop sending?* question leaves out health, the calendar, location and photos, which the Mac never sends. The phone's words do not change. `mac_shell_test.dart` checks the notes list and Settings.
- **2026-11-15** — Assumed (review): `mobile/README.md` says the Mac imports test checks every file the Mac entry reaches but `lib/controller.dart`, and that `controller_test.dart` checks the controller with no phone parts, because the test skips the controller.
- **2026-11-15** — Asked whether to ask Apple for a Developer ID certificate with the App Store Connect key now → chose yes, make it.
- **2026-11-15** — Asked how publishing handles the check on a real Mac, which needs the signed download from `main` → chose to check it after publishing; task 5.3 became an after-publishing step.
- **2026-11-15** — Assumed (review): the sign-in page (*This Mac has a key*, the webhook's *straight from this Mac* and *The Mac sends only while*, *Your notes stay on this Mac*), the webhook's problem line and the *Send your earlier notes too?* question say *Mac* on the Mac, through `Relay.device`; the Mac's webhook line leaves out health and places, which the Mac never sends. The phone's words do not change. `mac_shell_test.dart` checks the sign-in line.
- **2026-11-15** — Assumed: checkpoint saved with every task built but 5.2, which waits for the pull request's Mac build; the Developer ID certificate is still missing (Apple refused the key), so the Mac build on `main` skips the signed download until the person adds it.
