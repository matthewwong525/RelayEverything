import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/web/chats.dart';
import 'package:relay_app/web/space.dart';

// Saved AI chat transcripts in the browser, with a stand-in server, as App.test.tsx tested the React page.
final base = Uri.parse('https://relay.example.com/apps/relay/');
final now = DateTime.now().millisecondsSinceEpoch;
const chat1 = 'c0000000-0000-4000-8000-000000000001';
const chat2 = 'c0000000-0000-4000-8000-000000000002';
const chat3 = 'c0000000-0000-4000-8000-000000000003';

Map<String, Object?> listed(String id, String title, {bool savedByAi = false, int messages = 4, String? app = 'claude-code'}) =>
  {'id': id, 'title': title, 'project': 'relay-app', 'app': ?app, 'startedAt': now, 'lastAt': now,
    'messages': messages, 'savedByAi': savedByAi};

final chats = {'chats': [listed(chat1, 'Stiffener plan', savedByAi: true),
  listed(chat2, 'Fix the webhook signature', messages: 1, app: 'codex')], 'next': null, 'nextId': null};
final oneChat = {'chat': listed(chat1, 'Stiffener plan', savedByAi: true), 'next': 2,
  'saves': [{'id': 'e1', 'title': 'Stiffener plan', 'text': 'Use a 0.2 mm steel stiffener.', 'createdAt': now}],
  'messages': [
    {'seq': 0, 'role': 'you', 'text': 'How thick should the stiffener be?', 'at': now},
    {'seq': 1, 'role': 'step', 'text': 'Read pcb/board.kicad_pcb', 'at': now},
    {'seq': 2, 'role': 'ai', 'text': '0.2 mm is enough.', 'at': now},
  ]};
final more = {...oneChat, 'saves': <Object>[], 'next': null,
  'messages': [{'seq': 3, 'role': 'you', 'text': 'Save the plan to Relay Everything', 'at': now}]};

http.Response json(Object body, [int status = 200]) =>
  http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class Server {
  /// Each call as `METHOD route?query`, the route after `/apps/relay/api/`.
  final calls = <String>[];
  /// Answers that replace [ordinary] for one route.
  final answers = <String, http.Response Function()>{};

  http.Response ordinary(String call) {
    if (call == 'GET chats') return json(chats);
    if (call == 'GET chats?q=webhook') return json({...chats, 'chats': [listed(chat2, 'Fix the webhook signature', messages: 1)]});
    if (call == 'GET chats?q=nothing') return json({'chats': <Object>[], 'next': null, 'nextId': null});
    if (call == 'GET chat?id=$chat1') return json(oneChat);
    if (call == 'GET chat?id=$chat1&after=2') return json(more);
    if (call == 'GET chat?id=$chat2') return json({...more, 'chat': listed(chat2, 'Fix the webhook signature', messages: 1)});
    if (call == 'DELETE chat?id=$chat1') return json({'id': chat1});
    throw StateError('Unexpected request: $call');
  }

  late final client = MockClient((request) async {
    final route = request.url.path.replaceFirst('/apps/relay/api/', '');
    final call = '${request.method} $route${request.url.hasQuery ? '?${request.url.query}' : ''}';
    calls.add(call);
    return (answers[call] ?? () => ordinary(call))();
  });
}

Future<void> open(WidgetTester tester, Server server, {required bool wide}) async {
  tester.view.physicalSize = wide ? const Size(1400, 900) : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
    home: Scaffold(body: ChatsView(client: SpaceClient(base: base, client: server.client), wide: wide))));
  await tester.pumpAndSettle();
}

Future<void> search(WidgetTester tester, String words) async {
  await tester.enterText(find.byType(TextField), words);
  await tester.testTextInput.receiveAction(TextInputAction.search);
  await tester.pumpAndSettle();
}

void main() {
  for (final wide in [true, false]) {
    group(wide ? 'wide' : 'narrow', () {
      testWidgets('lists saved chats, finds them by a word, and says when none match', (tester) async {
        final server = Server();
        await open(tester, server, wide: wide);
        expect(find.text('AI chat transcripts'), findsOneWidget);
        expect(find.text('Stiffener plan'), findsOneWidget);
        expect(find.text('Saved by the AI'), findsOneWidget);
        // Each chat names its app in a small tag.
        expect([find.text('Claude Code'), find.text('Codex')], everyElement(findsOneWidget));
        expect(tester.getTopLeft(find.text('Codex')).dy, greaterThan(tester.getTopLeft(find.text('Fix the webhook signature')).dy));
        expect(find.textContaining(RegExp(r'^relay-app · .* · 1 message$')), findsOneWidget);
        expect(find.textContaining(RegExp(r'^relay-app · .* · 4 messages$')), findsOneWidget);

        await search(tester, ' webhook ');
        expect(find.text('Stiffener plan'), findsNothing);
        expect(find.text('Fix the webhook signature'), findsOneWidget);
        await search(tester, 'nothing');
        expect(find.text('No chat holds those words.'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await tester.pumpAndSettle();
        expect(find.text('Stiffener plan'), findsOneWidget);
        expect(server.calls, ['GET chats', 'GET chats?q=webhook', 'GET chats?q=nothing', 'GET chats']);
      });

      testWidgets('opens a chat with the AI save above its messages, and reads on', (tester) async {
        final server = Server();
        await open(tester, server, wide: wide);
        await tester.tap(find.text('Stiffener plan'));
        await tester.pumpAndSettle();
        expect(find.text('Written by the AI'), findsOneWidget);
        expect(find.text('Use a 0.2 mm steel stiffener.'), findsOneWidget);
        expect(find.text('How thick should the stiffener be?'), findsOneWidget);
        expect(find.text('Read pcb/board.kicad_pcb'), findsOneWidget);
        expect(find.textContaining(RegExp(r'^relay-app · [^·]*$')), findsOneWidget);
        expect(find.descendant(of: find.byType(BrandTag), matching: find.text('Claude Code')),
          wide ? findsNWidgets(2) : findsOneWidget, reason: 'the open chat names its app, and the wide list beside it too');
        final save = tester.getTopLeft(find.text('Use a 0.2 mm steel stiffener.'));
        expect(tester.getTopLeft(find.text('0.2 mm is enough.')).dy, greaterThan(save.dy));
        await tester.tap(find.text('Show more messages'));
        await tester.pumpAndSettle();
        expect(find.text('Save the plan to Relay Everything'), findsOneWidget);
        expect(find.text('Show more messages'), findsNothing);
        if (wide) {
          // The list stays beside the open chat.
          expect(find.text('Fix the webhook signature'), findsOneWidget);
        } else {
          await tester.pageBack();
          await tester.pumpAndSettle();
          expect(find.text('Fix the webhook signature'), findsOneWidget);
        }
        expect(server.calls, ['GET chats', 'GET chat?id=$chat1', 'GET chat?id=$chat1&after=2']);
      });

      testWidgets('loads older chats and more messages, and says when a part could not load', (tester) async {
        final server = Server();
        final older = 'GET chats?before=$now&beforeId=$chat2';
        server.answers['GET chats'] = () => json({...chats, 'next': now, 'nextId': chat2});
        server.answers[older] = () => http.Response('down', 502);
        server.answers['GET chat?id=$chat1&after=2'] = () => http.Response('down', 502);
        await open(tester, server, wide: wide);
        await tester.tap(find.text('Show older chats'));
        await tester.pumpAndSettle();
        expect(find.text('Older chats could not be loaded.'), findsOneWidget);
        server.answers[older] = () => json({'chats': [listed(chat3, 'Battery choice')], 'next': null, 'nextId': null});
        await tester.tap(find.text('Show older chats'));
        await tester.pumpAndSettle();
        expect(find.text('Battery choice'), findsOneWidget);
        expect(find.text('Older chats could not be loaded.'), findsNothing);
        expect(find.text('Show older chats'), findsNothing);

        await tester.tap(find.text('Stiffener plan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Show more messages'));
        await tester.pumpAndSettle();
        expect(find.text('More messages could not be loaded.'), findsOneWidget);
        server.answers.remove('GET chat?id=$chat1&after=2');
        await tester.tap(find.text('Show more messages'));
        await tester.pumpAndSettle();
        expect(find.text('Save the plan to Relay Everything'), findsOneWidget);
        expect(find.text('More messages could not be loaded.'), findsNothing);
      });

      testWidgets('says when a chat or the list could not be read, and reads it again', (tester) async {
        final server = Server();
        server.answers['GET chats'] = () => http.Response('down', 502);
        await open(tester, server, wide: wide);
        expect(find.text('Chats could not be loaded.'), findsOneWidget);
        server.answers.remove('GET chats');
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        server.answers['GET chat?id=$chat2'] = () => http.Response('down', 502);
        await tester.tap(find.text('Fix the webhook signature'));
        await tester.pumpAndSettle();
        expect(find.text('The chat could not be loaded.'), findsOneWidget);
        server.answers.remove('GET chat?id=$chat2');
        await tester.tap(find.text('Try again'));
        await tester.pumpAndSettle();
        expect(find.text('Save the plan to Relay Everything'), findsOneWidget);
      });

      testWidgets("deletes a chat after a confirm that says it can't be undone, and reads the list again", (tester) async {
        final server = Server();
        server.answers['DELETE chat?id=$chat1'] = () => http.Response('down', 502);
        await open(tester, server, wide: wide);
        await tester.tap(find.text('Stiffener plan'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Stiffener plan?'), findsOneWidget);
        expect(find.textContaining("You can't undo it."), findsOneWidget);
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Cancel')));
        await tester.pumpAndSettle();
        expect(server.calls.where((call) => call.startsWith('DELETE')), isEmpty);

        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
        await tester.pumpAndSettle();
        expect(find.text('The chat could not be deleted. Try again.'), findsOneWidget);

        server.answers.remove('DELETE chat?id=$chat1');
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Use a 0.2 mm steel stiffener.'), findsNothing);
        expect(find.widgetWithText(TextField, 'Search your chats'), findsOneWidget);
        expect(server.calls.where((call) => call.startsWith('DELETE')), ['DELETE chat?id=$chat1', 'DELETE chat?id=$chat1']);
        expect(server.calls.where((call) => call == 'GET chats'), hasLength(2));
      });
    });
  }

  test('a chat with no app came from Claude Code', () {
    expect([for (final app in [null, 'claude-code', 'codex']) ChatSummary.fromJson(listed(chat1, 'Plan', app: app)).appName],
      ['Claude Code', 'Claude Code', 'Codex']);
  });

  testWidgets('says how to start when there are no chats, and how to connect a computer from Claude Code or Codex',
      (tester) async {
    final server = Server();
    server.answers['GET chats'] = () => json({'chats': <Object>[], 'next': null, 'nextId': null});
    final opened = <Uri>[];
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light), home: Scaffold(body: ChatsView(
      client: SpaceClient(base: base, client: server.client), wide: true,
      opener: (address) async { opened.add(address); return true; }))));
    await tester.pumpAndSettle();
    expect(find.textContaining('No chats yet'), findsOneWidget);
    expect(find.text('Pick a chat to read it.'), findsOneWidget);
    await tester.tap(find.text('Connect a computer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('saves your Claude Code and Codex chats word for word'), findsOneWidget);
    for (final command in ['/plugin marketplace add matthewwong525/RelayEverything', '/plugin install relay@relay',
      'codex plugin marketplace add matthewwong525/RelayEverything', 'codex plugin add relay@relay', '/relay:connect']) {
      expect(find.text(command), findsOneWidget, reason: command);
    }
    expect(find.textContaining('can read all your Relay Everything data'), findsOneWidget);
    expect(find.textContaining('run your own Relay Everything server'), findsOneWidget);
    await tester.tap(find.text('Read the guide'));
    expect(opened.single.toString(), 'https://relayeverything.com/connections/claude-code/');
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });
}
