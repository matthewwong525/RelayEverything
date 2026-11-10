# Tasks

## 1. Outbox route filter

- [x] 1.1 Add a `private` filter (`true` = `privateRoutes`, `false` = note routes, `null` = all) to `Store.outbox` and `flush` in `mobile/lib/data/store.dart` and `mobile/lib/data/outbox.dart`, and add store and outbox tests that a note row flushes before an older health row when filtered, and that no row sends twice across the two filtered flushes

## 2. Controller: notes part, then private part

- [x] 2.1 Split `_sync()` in `mobile/lib/controller.dart` into a notes part (note-routes flush, status from it only, pull when wanted) and a private part (health, calendar, history, stays, points, private-routes flush, private client flush, photos) that never sets the status but `idle`, by design decisions 2 and 4
- [x] 2.2 Make `pullNotes()` return when the notes part ends, through a shared completer completed after the pull or when it cannot run, and in a `finally`, by design decision 3; drop `_pulling`
- [x] 2.3 Stop the private part at its next upload or photo while `_again` or a pull is waiting, and loop again starting with notes
- [x] 2.4 Write controller tests in `mobile/test/controller_test.dart` (or `sync_test.dart`) for each spec scenario: the pull shows a note from elsewhere before health rows send; a failed photo or health upload still pulls; the status is `synced` and `pullNotes` resolves while the private part still runs; a note kept during the private part goes before the remaining health rows; the existing sync tests still hold

## 3. Background round

- [x] 3.1 Reorder `backgroundRound` in `mobile/lib/sync/background.dart` to flush note routes and pull before the points, health, calendar, stays, private flush and photos, by design decision 5, and add a test in `mobile/test/sync_test.dart` that a waiting note goes before waiting health rows to the same server

## 4. Docs

- [x] 4.1 Update `site/src/content/docs/app/your-notes.md` (the sync state and *Your notes on every phone*) to say notes send and come in first and *Syncing* is about notes only, and `wiki/relay-phone-sync.md` *The round* and *Two places* to give the new order; verify `node scripts/product-name.test.mjs` passes

## 5. Checks

- [x] 5.1 Run `flutter analyze` and `flutter test` in `mobile/` and verify both pass
- [x] 5.2 `/save` the change, and verify CI's Flutter tests and both phone builds pass
