# Relay Everything app

Relay Everything keeps your thoughts. Type a note on your phone and it stays on your phone: you need no account, no key and no signal, and the app sends nothing. When you want to do more with your notes, turn on sending: each note then goes to your own Relay Everything server, which can pass it to your own database and your AI. With sending on, the app can also send your steps, heart rate, sleep, workouts and a history of the places you went. You read your health and places on your Relay Everything page, not in this app.

This is the phone app, for iPhone and Android. It is written in Flutter.

## What it does

- **Home.** The app opens on *Home*, a screen of folders like Apple Notes' *Folders*. The first card holds *Notes* (every note), *Voice notes* and *Shares* (notes with a photo, a file or a link), each with its count. *On this phone* holds *Location*, *Health*, *Calendar* and *Photos*, each with its status, such as *Off* or *Save battery · Sent 14:05*. *Connections* holds *Sending*, which says where the phone sends, then *AI apps* and *Webhooks*. Tap a header to fold it; the phone remembers. *Search* and *New note* stay at the bottom.
- **Notes.** A notes folder lists its notes, newest first, under its name, with *‹ Home* at the top left, in groups: *Today*, *Yesterday*, *Previous 7 days*, *Previous 30 days*, then by month. Each row shows the first line in bold, the time, the rest of the words, a *Voice* or *Typed* tag, and a small picture if the note has one. Under the title, a line gives the count and the sync state, such as *5 notes · Synced*, with a dot that pulses only while *Syncing*. With sending off, it says *On this phone*. With sending on, each note shows *Sent* or *Waiting to send*, and a waiting note goes on the next sync. Pull the list down to sync. Tap a row to read the whole note: its words, pictures, files, and *Play* for a voice note. You can not change a note after you save it.
- **Search.** Type in *Search* at the bottom, and the list shows only the notes with those words in their words, their place or their file names. On Home it finds notes in every folder; in a folder, only that folder's notes. It searches this phone only, with no signal. *Cancel* shows all the notes again.
- **The ⋯ menu.** The round ⋯ button at the top right of Home holds *Settings*; with sending on, *Sync now*; and with sending to a Relay Everything server, *Open your Relay Everything page*, which opens `<your-relay-server>/apps/relay/` in the phone's browser, where you sign in. Ring notes and recordings are there.
- **New note.** Tap the round green *New note* button at the bottom, type, and tap *Save*. The first line shows in bold. With *Pin notes to where I am* on, the note keeps where you are. This works with no signal. With sending off, the phone does not look up the place's name, so the note shows *Pinned*.
- **Voice notes.** Hold *New note* for half a second: the phone buzzes, the button turns amber with a mic, and it listens. Let go: it keeps listening. Talk, then tap anywhere on the screen to save, or tap *Cancel* to keep nothing. The phone writes the words itself with whisper.cpp, with no signal and no server, and the recording stays on the phone, out of iCloud and Google backups. The first time, the app asks before it gets the 57 MB speech model from whisper.cpp's page on Hugging Face; *Remove* in *Settings* deletes it. A tap shorter than half a second opens *New note* and records nothing. A recording with no words keeps nothing. With sending on, only the words go to your server, as a typed note.
- **Photos and files.** In *New note*, tap *Add photo or file* to add up to 10 photos or files, each up to 25 MB. They stay on the phone and show on the note's row and its page; tap one to open it. With sending on, each file goes after its note.
- **Apple Shortcuts** (iPhone, iOS 16 and later). Three actions: *Add a note*, *Get notes* and *Start a voice note*. *Start a voice note* opens the same listening card: tap anywhere to save. A note from a shortcut is kept and sent as a typed note is. *Get notes* reads only this phone.
- **Share from any app.** Share a web page, text, photos or a file into Relay Everything, add words, and tap *Save*. On iPhone and Android, the share card has the brand's paper color, the Inter font and a green *Save*, in light and dark.
- **Settings.** Open it from the ⋯ menu. It holds two groups: *Notes* (*Pin notes to where I am*) and *Voice notes* (the speech model).
- **Send my notes.** On the *Sending* page, under *Connections* on Home. Off until you turn it on. It asks where the phone sends: your Relay Everything server, or your own webhook, never both. For the server, the first time, you connect this phone: sign in from the app, or scan a key's QR code. For your own webhook, you type its address, copy its secret, and need no account: [`lib/data/webhook.dart`](lib/data/webhook.dart) signs each message in the server's webhook format. If you have notes from before, the app asks if they go too: *Send them*, or *Only new notes*. Turn it off, and new notes stay on the phone, notes already on your server stay there, and health, the calendar, location and photos stop.
- **Health** (only with sending on). The app reads steps, heart rate, sleep and workouts from Apple Health or Health Connect from the moment you turn it on, and sends them about every hour, also while the app is closed. The *Health* folder shows when they last went. With sending off, it says Health works with sending on, and *Turn on sending* asks where to send.
- **Location history** (only with sending on), in the *Location* folder. On Android, the app keeps a point each 100 m you move. On an iPhone, the phone keeps points while the app is closed: *Save battery* at each move of about 500 m and each arrival, or *Every 100 m*. A ring note then takes the nearest point within 10 minutes as its place.
- **Photos** (only with sending on), in the *Photos* folder. The app sends a copy of each new photo you take, at most 1,600 px on its long side, with when and where you took it, so your AI can see it. Photos wait for Wi-Fi unless *Send photos on mobile data* is on, and never hold back a note. They go where your notes go: your Relay Everything server, or your own webhook as `photo.created` messages. To add a photo to one note, use *Add photo or file*.
- **AI apps and Webhooks.** While the phone sends to a Relay Everything server, these rows show the names of the AI apps and webhooks you connected on your page, such as *Claude*. A tap opens that part of your page in the browser, to change it there. Otherwise each says *Sign in to see*, and a tap asks where to send.
- **Your server, your key.** The app talks only to the server you connect it to, with a key for this phone alone. The key only adds data, and reads the names of your AI apps and webhooks: it can not read, list or delete your notes or other data on your server. You can turn off one phone's key and keep the others.

Each permission is asked for only when you turn on its setting. With sending off, the app keeps no health or location history and makes no network call, except to get the speech model after you tap *Get it*.

## Get the app

- **Android:** download the `.apk` file from [the newest release](https://github.com/matthewwong525/RelayEverything/releases/latest) and open it on your phone. Android asks once to allow installs from your browser. Test builds from `main` are on [Releases](https://github.com/matthewwong525/RelayEverything/releases), marked *Pre-release*.
- **iPhone:** install the newest build from TestFlight, from the invite the owner sends you. After the first App Store release, the App Store has it too.

## Connect it to a server

Each phone sends with its own key. Sign in to your Relay Everything page and tap *Add a device*. The key shows once, as a QR code. In the app, open *Sending* on Home and turn on *Send my notes*, then tap *Scan the QR code*, or paste the key.

Or connect with no key to copy: tap *Sign in to connect* (*Use another server* for a server that is not `app.relayeverything.com`). The app opens the server's sign-in page inside the app, the person taps *Connect*, and the app trades the page's one-time code, with a secret only it holds, for its own key at `sign-in/phone/key`. The key holds the server's address. The app checks the key with the server's `key` route, which gives only the device name, never your data. The `connections` route gives only the names of your AI apps and webhooks. To try a preview, open *Sending*, tap *Server*, and enter the preview's address.

*Disconnect this phone*, on the *Sending* page, removes the key and turns sending off. Your notes stay on the phone.

The key is kept in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Build it yourself

1. Install Flutter (the version is in `pubspec.yaml`): https://docs.flutter.dev/get-started/install
2. Get the packages: `flutter pub get`
3. Check and test: `flutter analyze` and `flutter test`
4. Run it on a phone: `flutter run`

### Builds on GitHub

Each push that changes `mobile/` runs [`.github/workflows/mobile-ci.yml`](../.github/workflows/mobile-ci.yml). Its first job, `plan`, runs [`scripts/app-release.mjs`](../scripts/app-release.mjs) `version` to get the run's version and build number: you never edit the version in `pubspec.yaml`. Then it analyzes and tests, and builds both apps:

- **A branch or pull request builds and sends nothing.** The `.apk` is kept with the run, and the iPhone app is signed and checked, so a broken build shows before it lands.
- **A push to `main` sends a beta.** TestFlight gets the iPhone build, and a *Pre-release* tagged `mobile-v<version>+<build>` gets the `.apk`. It is never the latest release. Only the newest change sends: when a newer commit on `main` changes `mobile/`, the older run sends nothing, as the newer run sends its own build. A beta's version is the newest release's with its last number one higher, such as `1.1.1` after `v1.1.0`, because Apple takes no new TestFlight build for a version that is already live. Before the first release, it is the version in `pubspec.yaml`.
- **A tag `v<major>.<minor>.<patch>` on `main` releases the app.** See [Release the app](#release-the-app).

One counter, the run number, numbers every build on every branch and tag, so each build is higher than all before it.

- **Android** ([`mobile-android.yml`](../.github/workflows/mobile-android.yml)): signs with the upload key in these repository secrets:
  `RELAY_ANDROID_KEYSTORE_BASE64`, `RELAY_ANDROID_KEYSTORE_PASSWORD`, `RELAY_ANDROID_KEY_ALIAS`, `RELAY_ANDROID_KEY_PASSWORD`. When they are missing, a branch or beta file is signed with a debug key, and a release stops with the names of the missing secrets. A file signed with a debug key can never update to a signed one.
- **iPhone** ([`mobile-ios.yml`](../.github/workflows/mobile-ios.yml)): on a Mac, fastlane signs the build with one saved Apple Distribution certificate. Its `build` lane stops after the check of the speech parts; its `beta` lane also sends the build to TestFlight. Each build gets the app's App Store profiles from Apple, and never makes a certificate. It needs a paid Apple Developer Program membership, the app's record in App Store Connect (bundle id `com.matthewwong525.relayApp`), and these secrets:
  `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8` (the `.p8` file in base64), `APPLE_TEAM_ID`, and `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD`, which [`scripts/ios-signing-cert.mjs`](../scripts/ios-signing-cert.mjs) makes. Until they are set, the iPhone job ends with a notice that names the missing secrets and builds nothing; a release or a release check stops with those names instead.

- **iPhone device check** ([`mobile-device-check.yml`](../.github/workflows/mobile-device-check.yml)): only on request, never on a push. It builds the app for the iPhone simulator on a Mac, opens it, runs a fixed tour of Home and the notes list, a new note and Settings, and lets Claude try the change. You get a report, screenshots and a video. Start it with `/verify`, or put the label *check on iPhone* on a pull request. It needs no Apple key; Claude needs the secret `CLAUDE_CODE_OAUTH_TOKEN` (a Claude subscription token) or `ANTHROPIC_API_KEY`. See [the device check](../wiki/development/device-check.md).

Never commit a key, a keystore, a `.p8` file or a signing profile.

### Release the app

1. **Before the first release, fill in the App Store page.** In App Store Connect, add the description, screenshots, support and privacy addresses, age rating and privacy answers, and put the final privacy policy at its address. Apple needs them for its first review. A release changes only the *What's New* text.
2. **Check the steps with no release.** On GitHub, open *Actions*, then *Mobile CI*, then *Run workflow*, and tick `release_check`. Or run `gh workflow run mobile-ci.yml --ref main -f release_check=true`. Start it from `main` only: from a branch, it stops at once, because its build goes to TestFlight. The run does every step of a release with the next beta's version, and its iPhone build goes to TestFlight with the betas. But it sends nothing to App Store review, makes a draft GitHub release and deletes it, and marks no pull request.
3. **Tag a commit on `main`**, such as `v1.1.0`. On GitHub, open *Releases*, then *Draft a new release*, type the new tag, pick `main`, and publish: the run then adds the `.apk` and the notes to that release, and if the run fails, delete the release. Or run `git tag v1.1.0 origin/main && git push origin v1.1.0`. The tag sets the version. A tag that is not on `main`, is not in this form, or is not higher than the last release stops the run at once, with the reason.

The tag's run then:

1. Runs the full test: the analyzer and the Flutter tests, both signed builds with the check of the speech parts, and the fixed tour of [the device check](../wiki/development/device-check.md) on an iPhone simulator, each step required, with no Claude. One failure stops the release before anything goes to a store.
2. Writes the release notes with `app-release.mjs notes`: each pull request since the last `v*` tag that changed `mobile/`, grouped by its label (`enhancement` is *New*, `bug` is *Fixes*, the rest *Changes*). Changes to the server and the website are not listed.
3. Sends the iPhone build to App Store review with the notes as *What's New* (fastlane's `submit` lane). The first version in the App Store gets no *What's New*, because Apple takes none for it. Apple puts it live as soon as it approves.
4. Publishes the GitHub release *Relay Everything <version>* with the signed `.apk`, marked latest, so the website's *Android app* link opens it.
5. Marks each listed pull request with the label *released* and one comment, with `app-release.mjs mark`.

The job `release` can run again for the same tag: it does not send a version that is already in review or live, it edits the GitHub release, and it does not comment twice. To run a failed release again, use *Re-run failed jobs*, or re-run only the job `release`, never *Re-run all jobs*: that builds the iPhone app again with the same build number, and Apple refuses it.

**Apple takes one version in review at a time.** A new tag while the last version is still in review stops at `submit` with Apple's state. Run the job `release` again when that review ends.

## Where the code is

- `lib/data/`: the settings, the local store (SQLite through drift) that keeps every note, the sender that gives no API client while sending is off, the API client, and the outbox that sends waiting uploads in order.
- `lib/sync/`: health, location, photos and the hourly background sync, which run only while sending is on. On an iPhone, `native.dart` and `wake.dart` talk to `ios/Runner/RelayBackground.swift`, which keeps places and wakes the closed app for Health and places.
- `lib/voice/`: voice notes: the speech model's download, the recorder, and the words, written by whisper.cpp on the phone.
- `lib/shortcuts/`: the Apple Shortcuts bridge. `ios/Runner/RelayIntents.swift` has the actions; they talk to the app's Dart code on the `relay/shortcuts` channel, in the open app or in a hidden engine that runs `shortcutsMain`. A note the app could not take in time waits in `shortcuts-inbox/`, and the app keeps it on its next open.
- `lib/screens/`: Home with its folders, search, the ⋯ menu and *New note*; the notes list with its day groups; the Location, Health, Calendar and Sending pages; the listening card, the note page, new note, settings and connect.
- `test/`: unit tests for the store, outbox, API, sync, voice notes and Shortcuts, widget tests for each screen, and a test that no screen or job calls the network while sending is off.

This folder is part of [RelayEverything](https://github.com/matthewwong525/RelayEverything), Relay Everything's one public repository, under [its MIT license](../LICENSE). The old `relay-app` repository is a read-only copy.
