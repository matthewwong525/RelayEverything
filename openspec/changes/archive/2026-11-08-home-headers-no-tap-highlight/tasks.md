# Tasks

## 1. Header tap

- [x] 1.1 In `mobile/lib/screens/home.dart`, change `_FoldHeader` from `InkWell` to `GestureDetector(behavior: HitTestBehavior.opaque)`, keeping its `Semantics` and padding.
- [x] 1.2 In `mobile/test/screens_test.dart`, extend the fold test: no `InkWell` is an ancestor of the *On this phone* and *Connections* names, and the tap still folds.

## 2. Verify

- [x] 2.1 Run `flutter test` in `mobile/`; verify all pass with no check loosened.
