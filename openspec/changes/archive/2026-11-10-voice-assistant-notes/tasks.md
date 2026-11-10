## 1. Siri on the iPhone

- [x] 1.1 In `mobile/ios/Runner/RelayIntents.swift`, give `AddNoteIntent`'s `text` the title *Note*, its description and *What's the note?* as `requestValueDialog`, and lead the intent's description with what you say.
- [x] 1.2 Make `perform` ask for `text` when it has no words and no files, keep today's failure when no one can answer, and answer *Saved*.
- [x] 1.3 Add *Take a note in* and *Note in* phrases to `RelayShortcuts`, each with `.applicationName`.
- [x] 1.4 Add `INAlternativeAppNames` with *Relay* to `mobile/ios/Runner/Info.plist`.

## 2. Website and checks

- [x] 2.1 In `site/src/content/docs/app/shortcuts.md`, say what to tell Siri: one sentence on the new Siri, the question on other iPhones, and the short name; note the action's line now reads *Add Note with Files to Relay Everything*.
- [x] 2.2 Add the synonym and the spoken phrases to `ALLOWED` in `scripts/product-name.test.mjs`, as exact literals.

## 3. Checks

- [x] 3.1 Run `flutter test` in `mobile/`, the site tests, `node scripts/product-name.test.mjs` and `node scripts/public-check.mjs`; fix what fails. The iOS build runs in CI, the gate, because this computer can't build iOS.
