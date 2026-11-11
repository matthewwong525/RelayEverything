import 'dart:io';

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/relay.dart';

import 'screens_test.dart' show FakeRelay, openFolder, openSettings;

/// The app's own font, Inter from `assets/fonts/inter/`, so a width here is a width on a phone: the test font draws wider.
Future<void> loadInter() async {
  final font = File('assets/fonts/inter/InterVariable.ttf');
  await (FontLoader('Inter')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
}

/// A text with no line limit wraps instead of overflowing, so check that its one-line width fits its box. A large title
/// is there twice, large and small, and both must fit.
void expectOneLine(WidgetTester tester, String text) {
  for (final paragraph in tester.renderObjectList<RenderParagraph>(find.text(text))) {
    expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width), reason: '"$text" wraps');
  }
}

void main() {
  setUpAll(loadInter);

  testWidgets('at 360 px wide, the large titles, the Home rows, the switches and the Account choices show the whole name', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final relay = FakeRelay()
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.pumpAndSettle();
    for (final title in ['Home', 'Notes', 'On this phone', 'Calendar']) {
      expectOneLine(tester, title);
    }
    await openSettings(tester);
    for (final title in ['Settings', 'Pin notes to where I am']) {
      expectOneLine(tester, title);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openFolder(tester, 'Notes');
    for (final title in ['No notes', 'All 0', 'Voice 0', 'Photos and files 0']) {
      expectOneLine(tester, title);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tester.tap(find.byKey(const ValueKey('account')));
    await tester.pumpAndSettle();
    for (final title in ['Account', 'AI apps', 'Webhooks', 'Health, places, calendar and photos', 'Relay Everything',
        'Only my own webhook', 'Sign out']) {
      expectOneLine(tester, title);
    }
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openFolder(tester, 'Location');
    expectOneLine(tester, 'Location history');
    expect(tester.takeException(), isNull);
  });
}
