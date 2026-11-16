# Tasks

## 1. Phone

- [x] 1.1 `mobile/lib/data/store.dart`: `waiting()` counts distinct notes in the note routes, as design.md says. Verify: new `store_test.dart` tests: a note with two files and a change counts 1, two notes count 2, health, stays and calendar rows count 0.
- [x] 1.2 Update any test that expects the old count (search `waiting` in `mobile/test/`). Verify: `flutter test` passes.

## 2. Checks

- [x] 2.1 Run `flutter analyze` and `flutter test` in `mobile/`; all pass.
- [ ] 2.2 Run `/save`; the device check's notes list shows one waiting per note.
