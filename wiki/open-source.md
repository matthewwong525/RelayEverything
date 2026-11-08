# Open source

Relay Everything is one public repository, [matthewwong525/RelayEverything](https://github.com/matthewwong525/RelayEverything), under the [MIT license](../LICENSE). Part of [the wiki](README.md); the rule is in the Relay Everything section of [`AGENTS.md`](../AGENTS.md).

## What is public, and what is not

Everything in the repository is public: the server and web app in `app/`, the phone app in `mobile/`, the website in `site/`, the Claude Code plugin in [`plugin/`](../plugin/README.md) with its marketplace file in [`.claude-plugin/`](../.claude-plugin/marketplace.json), the ring in `cad/` and `pcb/`, and the plans and this wiki. `vendor/` keeps each library's own license.

These stay in Cloudflare, never in the repository: memory, company knowledge, notes, keys, and health and location data. A plan or wiki page is for anyone to read: write no person's phone number, address, email, health or place in it.

The IDs in `.agents/.wong-stack.json` and `app/wrangler.jsonc`, such as the account, Access app and database IDs, are not keys: Access still guards every route.

## The public check

[`scripts/public-check.mjs`](../scripts/public-check.mjs) refuses what must not go public. It names the file, and the commit for history, never the value:

- a key file or private note by its name: `.env` and `.dev.vars` files (not their `.example` copies), Apple and Android signing files such as `.p8`, `.p12`, `.jks` and `.mobileprovision`, a `*.private.*` file, or a `notes/` folder;
- text shaped like a key, such as a GitHub, AWS or Slack token, or a private key block;
- a value from `.env` or `app/.dev.vars` on this computer, but `CLOUDFLARE_ACCOUNT_ID`.

| Mode | What it reads | Where it runs |
|---|---|---|
| `--tree` (the default) | each file Git tracks or would track, as it is now | the Test job on GitHub, with no `.env`, and `npm test` in `app/`, which adds this computer's `.env` values |
| `--history` | each file in each commit that any ref reaches, and each commit message | by hand, before history goes anywhere new |
| `--notes` | lines in `openspec/`, `wiki/` and Markdown files of each commit that name a health or location value, a phone number, a street address, or an email no commit author uses | by hand: a list for a person to read; it never fails |

On `result=refused`, take the private detail out of the file. A refused file in history stays public in every copy once pushed: removing it means rewriting history, which changes every commit ID, so it waits for the person's decision. Never weaken the check to let a file through.

The [Relay Everything website's guard](relay-website.md#what-the-guard-refuses) uses the same rules, and adds its own.

## Phone builds

A change to `mobile/` runs [`mobile-ci.yml`](../.github/workflows/mobile-ci.yml) on GitHub: the Flutter tests, then both apps. A branch sends nothing: the Android file stays with the run. A publish to `main` sends its build to TestFlight and makes a *pre-release*, tagged `mobile-v<version>+<build>`, but only when no newer commit on `main` changes `mobile/`. A `v<x.y.z>` tag on `main` releases the app: after the full test, the iPhone app goes to App Store review, and the signed Android file becomes the latest GitHub release, which the website's *Android app* link opens. The iPhone build skips until the repository has the App Store Connect secrets that [`.env.example`](../.env.example) names. [`mobile/README.md`](../mobile/README.md#release-the-app) has the steps.

- **The App Store Connect key must have the Admin role.** The script makes the certificate, and each iPhone build makes its App Store profiles. A key with a lower role, such as App Manager, can't do these.
- **One saved Apple Distribution certificate signs every iPhone build.** It is in the secrets `IOS_DIST_CERT_P12` and `IOS_DIST_CERT_PASSWORD`, and each build gets the App Store profiles for it from Apple. A build never makes a certificate: an old build that signed automatically made a new *Apple Development: Created via API* certificate each run, until the account was full.
- **Renew the certificate each year with `node scripts/ios-signing-cert.mjs`.** It runs on this computer with the App Store Connect key in `.env`, keeps a saved certificate that has more than 30 days left, and else makes a new one. It writes both values to `.env` and to the repository's secrets, and prints only `result=`, the certificate id and its expiry; `--renew` makes a new one at once. The saved one ends on 2027-11-07. The next build then makes new profiles by itself.
- **When Apple's account is full, a person revokes a certificate.** The script prints `result=full`, or a build fails with *Choose a certificate to revoke*. First list the certificates through the App Store Connect API (`GET /v1/certificates`, signed with `ASC_KEY_ID`, `ASC_ISSUER_ID` and the base64 `ASC_KEY_P8`) and the running iPhone builds: a revoke while a build signs breaks that build. Then, after the person's yes, revoke each *Apple Development: Created via API* certificate on the [Certificates page](https://developer.apple.com/account/resources/certificates/list), or with `DELETE /v1/certificates/<id>`. A revoked certificate can't come back. Keep the *Developer ID Application* certificate and the saved one.
- **The key can't make an App Group.** The build also doesn't register a new app part. A new bundle id in `SIGNED_TARGETS` of [`Fastfile`](../mobile/ios/fastlane/Fastfile) fails the build with *app not found* until you register it on the [Identifiers page](https://developer.apple.com/account/resources/identifiers/list). If the part uses the App Group, register the group once on the [App Groups page](https://developer.apple.com/account/resources/identifiers/list/applicationGroup) and turn it on for each app ID under *App Groups → Configure*. Else the build fails with *Provisioning profile … doesn't match the entitlements file's value for the com.apple.security.application-groups entitlement*. Then build again. Relay Everything's group is `group.com.matthewwong525.relayApp`.
- **A package whose Dart code finds native functions by name loses them in a Release iPhone build.** Such a package calls `DynamicLibrary.process()`, as `whisper_cpp_flutter_plus` does for its `wf_*` functions. Nothing in the app calls those functions directly, so the link can leave them out and the archive's strip can remove their names: the app then fails only on a phone. Keep each one with `-Wl,-u,_<name>` in Runner's Release and Profile `OTHER_LDFLAGS`, set `STRIP_STYLE = non-global`, and check the `.ipa` with `nm -gU` before TestFlight, as `check_speech_parts` in [`mobile/ios/fastlane/Fastfile`](../mobile/ios/fastlane/Fastfile) does.
- **On the Linux build computer, Flutter is in `/opt/flutter/bin`, not on `PATH`.** Run `export PATH=/opt/flutter/bin:$PATH` before `flutter pub get`, `flutter analyze` and `flutter test` in `mobile/`.

## Run your own server

Anyone can run Relay Everything in their own Cloudflare account: [`self-host/SETUP.md`](../self-host/SETUP.md) is the guide an AI follows, over [`self-host/setup.mjs`](../self-host/setup.mjs). An install deploys the same Relay Everything files as this repository's app, through its own entry, [`app/worker/relay-only.ts`](../app/worker/relay-only.ts), and its own page build, `npm run build:relay-only`. It carries none of WongStack.

- **A new Relay Everything binding goes in the install too.** Add it to [`self-host/wrangler.template.jsonc`](../self-host/wrangler.template.jsonc) beside [`app/wrangler.jsonc`](../app/wrangler.jsonc); [`bindings.test.mjs`](../self-host/bindings.test.mjs) fails, by name, on one the install lacks, or else every install breaks at its next update.
- **A Relay Everything migration reads only `relay_` tables.** An install applies every migration, so WongStack's tables are there but empty.
- **Relay Everything has no end-to-end encryption.** Data lives on a Relay Everything server or only on the phone. A person who wants more control runs their own server.
- **A device key only adds data**, and a phone's key changes only the notes that phone sent. It reads nothing on any server, so a person's data stays theirs: [Keys](https://relayeverything.com/api/keys/).

## Pull requests from outside

Anyone can open a pull request. Its checks run with none of the project's keys, and nothing deploys from it: [CI on GitHub Actions](stack/github-actions.md#where-the-deploy-key-is) says why.
