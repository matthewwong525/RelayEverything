# Tasks

## 1. Server: connect a phone by signing in

- [x] 1.1 Add `schema/migrations/<timestamp>_relay_phone_codes.sql` (`code_sha256`, `person_id`, `name`, `challenge`, `expires_at`) and list the table in `wiki/relay-spaces.md#the-directory`; verify the migration test and `space-schema.test.ts` pass.
- [x] 1.2 Move the device-making part of `deviceAdd` (`device.ts`) into one shared function, used by *Add a device* and the phone trade; verify `device.test.ts` passes unchanged.
- [x] 1.3 Add `sign-in/phone.ts`: `GET phone` (signed out → sign-in then back; signed in → *Connect this phone?* page with the name field), `POST phone` (Origin checked; stores the code's SHA-256 for 5 minutes; redirects to `relayeverything://connected?code=`), *Cancel* to `?error=cancelled`, and `POST phone/key` (Origin-exempt, rate-limited; checks SHA-256(verifier) against the challenge, deletes the row, makes the device and key, answers `{server, key}`). Write `phone.test.ts` first: the happy path, a code used twice, after 5 minutes, a wrong verifier, a POST from another origin, a key that then reaches only phone routes and the person's own space; verify `npm test` in `app/` passes.
- [x] 1.4 Run `npm run relay:api-doc` in `app/` and update `site/src/content/docs/api/keys.md` with the sign-in way; verify the API doc test passes.

## 2. Phone: the in-app sign-in

- [x] 2.1 Add `flutter_web_auth_2` to `mobile/pubspec.yaml`, the `relayeverything` scheme to `Info.plist` and its callback activity to the Android manifest; verify `flutter pub get` and `flutter analyze` pass.
- [x] 2.2 Add the sign-in connect to `RelayController`/`Relay` (verifier, challenge, open the page, trade the code, check with `GET key`, save in the Keychain) behind an injectable web-auth function, and the new `ConnectScreen` layout (*Sign in to connect*, *Use another server*, QR, paste); write controller and widget tests with a fake web auth and fake API: success, cancel, refused code, another server, and no network call while sending is off before the switch opens the screen; verify `flutter test` passes, `offline_test.dart` included.

## 3. Phone: health and places in the background on iPhone

- [x] 3.1 Add `lib/sync/wake.dart` (`wakeRound` entry point on `relay/wake`), the `relay/background` `set {health, history, mode}` call from the controller at start and on each settings change, and the points-file drain (with up to 10 names while sending is on); write tests for the drain, the flags each way (sending off → both false), and a Health read that fails while locked leaving `health.since` unchanged; verify `flutter test` passes.
- [x] 3.2 On iPhone, route history through the points file instead of the geolocator stream (Android keeps `PhonePlaces.history()`), and drain the file each minute while the app is open; verify the controller tests for history on, off and sending off pass.
- [x] 3.3 Write the Swift `BackgroundWake` (headless engine, one wake at a time, 25 s cap), the HealthKit observer queries with hourly background delivery registered in `didFinishLaunchingWithOptions`, and the `CLLocationManager` in two modes after OwnTracks (*Save battery*: significant changes + visits + `requestLocation` on wake; *Every 100 m*: continuous updates kept at 100 m or a 5-minute timer, no automatic pause, plus significant changes for relaunch), restarted on relaunch, writing the points file (excluded from backup), all following the `UserDefaults` flags; verify `flutter build ios --simulator --no-codesign` succeeds.
- [x] 3.4 Add the *Save battery* / *Every 100 m* choice under *Location history* (iPhone only, saved in settings, sent to Swift); write widget and controller tests for the default, a switch, and its absence on Android; verify `flutter test` passes.
- [x] 3.5 Record `sent.health` and `sent.points` in `flush`, and show *Sent HH:mm · N waiting* under *Health* and *Location history* in Settings; write store and widget tests; verify `flutter test` passes.

## 4. Docs

- [x] 4.1 Update `site/src/content/docs/start/connect-a-phone.md` (sign in from the app first, QR second), `app/health.md` and `app/location.md` (when the iPhone sends, the Settings line, the two location modes and their battery use, a swipe-up close stops location until the app opens), and `mobile/README.md`; verify `node scripts/product-name.test.mjs` passes and the site builds with `node scripts/publish-relay-site.mjs --ref HEAD --staging`.

## 5. Checks

- [x] 5.1 Run `flutter analyze`, `flutter test` in `mobile/`, `npm test` in `app/`, and `node scripts/public-check.mjs`; all pass.
- [ ] 5.2 `/save`, then deploy the directory migration and the staging shared server by hand ([the Workers and their order](../../../wiki/relay-spaces.md#the-workers-and-their-order)), and run the iPhone device check (`/verify`) with the connect screen, a simulated sign-in return and a simulated drive (`simctl location`) with the app closed in each mode; verify the report shows the new screens and points kept after the app was closed.
- [ ] 5.3 After publish to TestFlight, the person's own check on their iPhone: connect by signing in, close the app, walk and move 1 km in *Save battery*, then a short trip in *Every 100 m*, and see steps and points on their Relay Everything page within a few hours with the Settings lines matching.
