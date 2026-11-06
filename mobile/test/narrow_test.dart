import 'dart:io';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/relay.dart';

import 'screens_test.dart' show FakeRelay;

/// The phone's own font, from the Flutter SDK, so a width here is a width on a phone: the test font draws wider.
Future<void> loadRoboto() async {
  final tester = Platform.resolvedExecutable;
  final sdk = tester.substring(0, tester.indexOf('${Platform.pathSeparator}bin${Platform.pathSeparator}cache'));
  final font = File([sdk, 'bin', 'cache', 'artifacts', 'material_fonts', 'Roboto-Regular.ttf'].join(Platform.pathSeparator));
  await (FontLoader('Roboto')..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())))).load();
}

RenderParagraph paragraphOf(WidgetTester tester, String text) => tester.renderObject<RenderParagraph>(find.text(text));

/// A text with no line limit wraps instead of overflowing, so check that its one-line width fits its box.
void expectOneLine(WidgetTester tester, String text) {
  final paragraph = paragraphOf(tester, text);
  expect(paragraph.getMaxIntrinsicWidth(double.infinity), lessThanOrEqualTo(paragraph.size.width), reason: '"$text" wraps');
}

void main() {
  setUpAll(loadRoboto);

  testWidgets('at 360 px wide, the timeline title and the Settings switch show the whole name', (tester) async {
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
    expectOneLine(tester, 'Relay Everything');
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expectOneLine(tester, 'Send to Relay Everything');
    expect(tester.takeException(), isNull);
  });
}
