import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/web/connection_page.dart';

import 'web_space_fixture.dart';

void main() {
  late FakeSpace space;
  late List<Uri> opened;
  late int count;

  setUp(() {
    space = FakeSpace();
    opened = [];
    count = 1234;
    space.answers.addAll({
      'GET photos': (_) => {'count': count},
      'POST photos/delete': (_) {
        final deleted = count;
        count = 0;
        return {'deleted': deleted};
      },
    });
  });

  Future<void> show(WidgetTester tester, ConnectionKind kind) async {
    windowOf(tester, const Size(1280, 900));
    await tester.pumpWidget(themed(Scaffold(body: ConnectionPage(kind: kind, client: space.client,
      opener: (address) async { opened.add(address); return true; }))));
    await tester.pumpAndSettle();
  }

  for (final kind in [ConnectionKind.location, ConnectionKind.health, ConnectionKind.calendar]) {
    testWidgets('${kind.title} says the phone sends it, leads to the app, and reads no data', (tester) async {
      await show(tester, kind);
      expect(find.text(kind.title), findsOneWidget);
      expect(find.textContaining('Your phone sends ${kind.what} to Relay Everything.'), findsOneWidget);
      await press(tester, find.text('App Store'));
      await press(tester, find.text('Android'));
      await press(tester, find.text('How to install the app'));
      expect(opened, [Uri.parse(appStoreLink), Uri.parse(androidLink), Uri.parse('https://relayeverything.com/start/install/')]);
      expect(opened.first.host, 'apps.apple.com');
      // No call to the space: no health, place or calendar data is read, so none can show.
      expect(space.calls, isEmpty);
    });
  }

  testWidgets('Photos counts the photos and deletes all of them only after a confirm', (tester) async {
    await show(tester, ConnectionKind.photos);
    expect(find.text('App Store'), findsOneWidget);
    expect(find.text('1,234 photos sent from your phones.'), findsOneWidget);
    await press(tester, find.text('Delete all photos'));
    expect(find.text('Delete all photos?'), findsOneWidget);
    await press(tester, find.text('Cancel'));
    expect(space.count('POST photos/delete'), 0);
    await press(tester, find.text('Delete all photos'));
    await press(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete all photos')));
    expect(space.sent('POST photos/delete'), [{'confirm': 'delete'}]);
    expect(find.text('No photos yet'), findsOneWidget);
    expect(find.text('Delete all photos'), findsNothing);
    expect([for (final (route, _) in space.calls) route], ['GET photos', 'POST photos/delete', 'GET photos']);
  });

  testWidgets('Photos says one photo, and says why a delete did not work', (tester) async {
    count = 1;
    space.answers['POST photos/delete'] = (_) => refusal(500, 'The photos could not be deleted. Try again.');
    await show(tester, ConnectionKind.photos);
    expect(find.text('1 photo sent from your phones.'), findsOneWidget);
    await press(tester, find.text('Delete all photos'));
    await press(tester, find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete all photos')));
    expect(find.text('The photos could not be deleted. Try again.'), findsOneWidget);
    expect(find.text('1 photo sent from your phones.'), findsOneWidget);
  });

  testWidgets('Photos with no client shows only the way to the app', (tester) async {
    windowOf(tester, const Size(1280, 900));
    await tester.pumpWidget(themed(const Scaffold(body: ConnectionPage(kind: ConnectionKind.photos))));
    await tester.pumpAndSettle();
    expect(find.text('App Store'), findsOneWidget);
    expect(find.textContaining('photos sent'), findsNothing);
  });
}
