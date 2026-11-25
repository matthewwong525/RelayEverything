import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/editor/web_note/web_note_pool.dart';

import 'fakes.dart';

/// Every test file in this folder: a note opens a fake editor page, as no web view runs in a test. Each test gets a
/// pool of its own.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  setUp(() => WebNotePool.shared = fakePool());
  await testMain();
}
