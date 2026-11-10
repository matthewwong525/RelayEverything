import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/web/space.dart';

/// A made-up Relay Everything server for the browser's pages: each route answers from [answers], keyed like
/// `GET devices`, and each call is kept in [calls]. A route with no answer is refused, so a test sees it.
class FakeSpace {
  final calls = <(String, Object?)>[];
  final answers = <String, Object? Function(Object? body)>{};

  late final client = SpaceClient(base: Uri.parse('https://relay.example.com/apps/relay/'), client: MockClient((request) async {
    final route = '${request.method} ${request.url.path.substring('/apps/relay/api/'.length)}';
    final body = request.body.isEmpty ? null : jsonDecode(request.body);
    calls.add((route, body));
    final answer = answers[route];
    if (answer == null) return http.Response(jsonEncode({'error': {'message': 'Unexpected $route'}}), 404);
    final value = answer(body);
    return value is http.Response ? value : http.Response(jsonEncode(value), 200, headers: {'content-type': 'application/json'});
  }));

  /// The bodies sent to [route], such as `POST devices/off`.
  List<Object?> sent(String route) => [for (final (called, body) in calls) if (called == route) body];

  int count(String route) => sent(route).length;
}

/// A refusal as the server words it.
http.Response refusal(int status, String message) =>
  http.Response(jsonEncode({'error': {'code': 'refused', 'message': message}}), status, headers: {'content-type': 'application/json'});

/// The few parts of [Relay] the browser's Settings use; any other member is never called.
class TinyRelay extends Relay {
  @override
  Settings settings = const Settings();
  final calls = <String>[];

  @override
  RelayPlatform get platform => RelayPlatform.web;

  @override
  Future<void> setAppearance(Appearance appearance) async {
    calls.add('appearance ${appearance.name}');
    settings = settings.copyWith(appearance: appearance);
    notifyListeners();
  }

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// A window of [size], set back after the test.
void windowOf(WidgetTester tester, Size size) {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Keeps what the page copies, as the browser's clipboard would.
List<String> catchCopies(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return copied;
}

/// [child] in the app's own theme.
Widget themed(Widget child) => MaterialApp(theme: brandTheme(Brightness.light), home: child);

/// Scrolls [finder] into view, then taps it and waits for the answers.
Future<void> press(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
