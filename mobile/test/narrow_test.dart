import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/relay.dart';

import 'screens_test.dart' show FakeRelay, openSettings;

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

  testWidgets('at 360 px wide, the large titles and the Settings switches show the whole name', (tester) async {
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
    expectOneLine(tester, 'Notes');
    expectOneLine(tester, 'No notes ·');
    await openSettings(tester);
    for (final title in ['Settings', 'Send my notes', 'Health', 'Pin notes to where I am']) {
      expectOneLine(tester, title);
    }
    expect(tester.takeException(), isNull);
  });
}
