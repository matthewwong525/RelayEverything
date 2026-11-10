import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/relay.dart';

import 'screens_test.dart' show FakeRelay, newNote, openFolder, openSettings;

/// Each icon drawn now from Material's own font, such as an app bar's default back arrow or a segment's check.
Finder materialIcons() => find.byWidgetPredicate((widget) => widget is Icon && widget.icon?.fontFamily == 'MaterialIcons');

void main() {
  test('the app draws only Cupertino icons, as Apple Notes does', () {
    final material = RegExp(r'(?<![A-Za-z])Icons\.');
    final left = [
      for (final file in Directory('lib').listSync(recursive: true).whereType<File>())
        if (file.path.endsWith('.dart') && material.hasMatch(file.readAsStringSync())) file.path,
    ];
    expect(left, isEmpty, reason: 'Use CupertinoIcons in place of Icons');
  });

  testWidgets('no page draws a Material icon by default, such as a back arrow or a check', (tester) async {
    final relay = FakeRelay()..entries = [Entry(id: 'n1', text: 'Shop\n- [ ] Eggs', at: DateTime.now())];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(materialIcons(), findsNothing, reason: 'Home');
    Future<void> back() async {
      await tester.pageBack();
      await tester.pumpAndSettle();
    }
    for (final folder in ['Location', 'Health', 'Calendar', 'Photos']) {
      await openFolder(tester, folder);
      expect(materialIcons(), findsNothing, reason: folder);
      await back();
    }
    await openFolder(tester, 'Notes');
    expect(materialIcons(), findsNothing, reason: 'the notes list');
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'a new note');
    await back();
    await tester.tap(find.text('Shop'));
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'a note');
    await back();
    await back();
    await openSettings(tester);
    expect(materialIcons(), findsNothing, reason: 'Settings');
    await tester.tap(find.byKey(const ValueKey('account')));
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'the Sign in page');
    await tester.tap(find.text("Don't want an account? Use your own webhook"));
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'the Sign in page, My own webhook picked');
    await back();
    // The Account page, signed in.
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('account')));
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'the Account page');
    await tester.tap(find.text('Webhooks'));
    await tester.pumpAndSettle();
    expect(materialIcons(), findsNothing, reason: 'Webhooks');
  }, variant: const TargetPlatformVariant({TargetPlatform.android, TargetPlatform.iOS}));
}
