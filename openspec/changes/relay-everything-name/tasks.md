# Tasks

## 1. Phone app (`mobile/`)

- [x] 1.1 Set `android:label` in `mobile/android/app/src/main/AndroidManifest.xml` and `CFBundleDisplayName` and `CFBundleName` in `mobile/ios/Runner/Info.plist` to `Relay Everything`; change every usage string in `Info.plist` to name *Relay Everything*. Keep `applicationId`, the bundle ID and `pubspec.yaml`'s `name`. Verify with `git diff` that no ID line changed.
- [x] 1.2 Change every string a person reads in `mobile/lib/` (`app.dart` title, `controller.dart` messages, `screens/*.dart`, `sync/location.dart` notification) to *Relay Everything*; keep the `Relay` and `RelayController` classes. Update the matching assertions in `mobile/test/`, and add a widget test that the timeline title and the Settings switch fit at 360 px wide; verify with `flutter test` in `mobile/`.
- [x] 1.3 Update `mobile/README.md` prose.

## 2. Server page and AI connector (`app/`)

- [x] 2.1 Change the strings in `app/src/apps/relay/*.tsx`, `app/src/apps/relay/app.json` and the `<title>` in `app/vite.config.ts`; update `App.test.tsx` and `Webhooks.test.tsx`.
- [x] 2.2 Change `app/worker/relay-mcp/auth.ts` HTML, `tools.ts` (`title` and `instructions`; `name: "relay"` stays) and `index.ts` (`resource_name`); update `auth.test.ts` and `tools.test.ts`.
- [x] 2.3 Change refusal messages and route descriptions in `app/worker/apps/relay/*.ts` and the schema descriptions in `webhooks/format.ts`; update their tests. Run `npm run relay:api-doc` in `app/` and regenerate `site/public/webhooks/v1.schema.json` from `format.ts`; verify the drift tests pass.

## 3. Website (`site/`)

- [x] 3.1 Change `site/astro.config.mjs` (title, description, GitHub label), every page in `site/src/content/docs/`, and `site/public/webhooks/receiver.mjs` messages; update `site/tests/` assertions. Verify with `npm test` in `site/`.

## 4. Plugin, scripts, ring and docs

- [x] 4.1 Change descriptions and titles in `plugin/.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` (keep `name: "relay"`), messages in `plugin/bin/*.mjs`, `plugin/skills/*/SKILL.md` and `plugin/README.md`; update `plugin/test/`.
- [x] 4.2 Change messages a person reads in `self-host/setup.mjs`, `scripts/relay-device-key.mjs` (the key page and terminal text) and `scripts/relay-mcp-*.mjs`; update their tests.
- [x] 4.3 Change prose in `README.md`, `AGENTS.md`, `self-host/SETUP.md`, `cad/README.md`, `pcb/PLAN.md`, `pcb/SCHEMATIC.md` and `wiki/**` (the ring is *the Relay Everything ring*); keep link targets and file names.

## 5. The name check

- [x] 5.1 Write `scripts/product-name.test.mjs` by design.md: it reads the listed user-facing files and fails on a bare *Relay* with the file and line, with a literal allow-list; include its own cases (a bare *Relay* in a docs page fails; *Relay Everything*, `/relay:saving`, `RELAY_SAVE` and `apps/relay` pass). Add it to the `node --test` list in `app/package.json`'s `test` script.

## 6. Checks

- [x] 6.1 Run the pre-checks once: `npm test` in `app/` and `site/`, `flutter test` in `mobile/`, `node --test scripts/*.test.mjs`, `node scripts/public-check.mjs`, and `npm run relay:api-doc` in `app/` with no diff. Fix each failure; loosen no check.
- [ ] 6.2 After implementation, `/save`, then check the preview: the server page heading and the website at relay-staging.matthewwong525.workers.dev show *Relay Everything*, and the CI Android build installs over the earlier app with notes kept.
