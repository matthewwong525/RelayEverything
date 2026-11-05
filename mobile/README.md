# Relay app

Relay keeps your thoughts. Type a note on your phone and it stays on your phone: you need no account, no key and no signal, and the app sends nothing. When you want to do more with your notes, turn on sending: each note then goes to your own Relay server, which can pass it to your own database and your AI. With sending on, the app can also send your steps, heart rate, sleep, workouts and a history of the places you went. Ring notes from a Pebble Index ring go to your server too. You read them on your Relay page, not in this app.

This is the phone app, for iPhone and Android. It is written in Flutter.

## What it does

- **Timeline.** The notes you made on this phone, newest first. With sending off, the top of the screen says *On this phone*. With sending on, each note shows *Sent* or *Waiting to send*, and a waiting note goes on the next sync. A card at the top says that ring notes and recordings are on your Relay page; *Open your Relay page* opens `<your-relay-server>/apps/relay/` in the phone's browser, where you sign in.
- **New note.** Tap *New note*, type, and tap *Save*. With *Pin notes to where I am* on, the note keeps where you are. This works with no signal. With sending off, the phone does not look up the place's name, so the note shows *Pinned*.
- **Voice notes.** Hold *Hold to talk*, talk, and let go. The phone writes the words itself with whisper.cpp, with no signal and no server, and the recording stays on the phone, out of iCloud and Google backups. The first time, the app asks before it gets the 57 MB speech model from whisper.cpp's page on Hugging Face; *Remove* in *Settings* deletes it. A press shorter than half a second, or a recording with no words, keeps nothing. With sending on, only the words go to your server, as a typed note.
- **Send to your Relay server.** Off until you turn it on. The first time, you connect this phone's key. If you have notes from before, the app asks if they go too: *Send them*, or *Only new notes*. Turn it off, and new notes stay on the phone, notes already on your server stay there, and health and location stop.
- **Health** (only with sending on). The app reads steps, heart rate, sleep and workouts from Apple Health or Health Connect from the moment you turn it on, and sends them every hour.
- **Location history** (only with sending on). The app keeps a point each 100 m you move. A ring note then takes the nearest point within 10 minutes as its place.
- **Your server, your key.** The app talks only to the server you connect it to, with a key for this phone alone. The key only adds data: it can not read, list or delete anything on your server. You can turn off one phone's key and keep the others.

Each permission is asked for only when you turn on its setting. With sending off, the app keeps no health or location history and makes no network call, except to get the speech model after you tap *Get it*.

## Get the app

- **Android:** download the newest `.apk` file from [Releases](https://github.com/matthewwong525/RelayEverything/releases/latest) and open it on your phone. Android asks once to allow installs from your browser.
- **iPhone:** install the newest build from TestFlight, from the invite the owner sends you.

## Connect it to a server

A Relay server is a private site behind Cloudflare Access. Its owner makes a key for each phone:

```
node scripts/relay-device-key.mjs create --name "Android phone"
```

The key shows once, as a QR code. In the app, open *Settings* and turn on *Send to your Relay server*, then tap *Scan the QR code*, or paste the key. The key holds the server's address. The app checks the key with the server's `key` route, which gives only the device name, never your data. To try a preview, open *Settings*, tap *Server*, and enter the preview's address.

*Disconnect this phone*, in *Settings*, removes the key and turns sending off. Your notes stay on the phone.

The key is kept in the iPhone Keychain or the Android Keystore, never in the app's own files.

## Build it yourself

1. Install Flutter (the version is in `pubspec.yaml`): https://docs.flutter.dev/get-started/install
2. Get the packages: `flutter pub get`
3. Check and test: `flutter analyze` and `flutter test`
4. Run it on a phone: `flutter run`

### Builds on GitHub

Each push that changes `mobile/` runs [`.github/workflows/mobile-ci.yml`](../.github/workflows/mobile-ci.yml): analyze and test, then:

- **Android** ([`mobile-android.yml`](../.github/workflows/mobile-android.yml)): on `main`, a release with a signed `.apk`, tagged `mobile-v<version>+<build>`; on any other branch, the `.apk` as a run artifact. It signs with the upload key in these repository secrets, or with a debug key when they are missing:
  `RELAY_ANDROID_KEYSTORE_BASE64`, `RELAY_ANDROID_KEYSTORE_PASSWORD`, `RELAY_ANDROID_KEY_ALIAS`, `RELAY_ANDROID_KEY_PASSWORD`.
- **iPhone** ([`mobile-ios.yml`](../.github/workflows/mobile-ios.yml)): on a Mac, fastlane signs the build automatically and sends it to TestFlight. It needs a paid Apple Developer Program membership, the app's record in App Store Connect (bundle id `com.matthewwong525.relayApp`), and these secrets:
  `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8` (the `.p8` file in base64), `APPLE_TEAM_ID`. Until they are set, the iPhone job ends with a notice and builds nothing.

Never commit a key, a keystore, a `.p8` file or a signing profile.

## Where the code is

- `lib/data/`: the settings, the local store (SQLite through drift) that keeps every note, the sender that gives no API client while sending is off, the API client, and the outbox that sends waiting uploads in order.
- `lib/sync/`: health, location and the hourly background sync, which run only while sending is on.
- `lib/voice/`: voice notes: the speech model's download, the recorder, and the words, written by whisper.cpp on the phone.
- `lib/screens/`: timeline with *Hold to talk* and the card that opens your Relay page, new note, settings and connect.
- `test/`: unit tests for the store, outbox, API, sync and voice notes, widget tests for each screen, and a test that no screen or job calls the network while sending is off.

This folder is part of [RelayEverything](https://github.com/matthewwong525/RelayEverything), Relay's one public repository, under [its MIT license](../LICENSE). The old `relay-app` repository is a read-only copy.
