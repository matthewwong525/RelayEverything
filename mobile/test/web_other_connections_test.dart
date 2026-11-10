import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/web/other_connections.dart';

import 'web_space_fixture.dart';

// Connect your AI and Email notes in the browser, with a stand-in server and made-up names and addresses.
final now = DateTime.now().millisecondsSinceEpoch;
const connector = 'https://mcp.example.com';

void main() {
  late FakeSpace space;
  late Map<String, Object?> connections;
  late List<Uri> opened;
  late int savedChats;

  setUp(() {
    space = FakeSpace();
    opened = [];
    savedChats = 0;
    connections = {
      'email': 'you@example.com',
      'devices': [
        {'id': 'd1', 'name': 'iPhone', 'kind': 'phone', 'since': now},
        {'id': 'd4', 'name': 'Work Mac', 'kind': 'computer', 'since': now, 'lastChatAt': null},
      ],
      'aiApps': [{'name': 'Claude', 'connectedAt': now}],
      'webhooks': <Object?>[],
      'notesAddress': 'notes-k7q2m9xwab@in.example.com',
      'sharedAddress': 'notes@in.example.com',
    };
    space.answers.addAll({
      'GET connections': (_) => connections,
      'GET ai-apps': (_) => {'address': connector, 'apps': [
        {'id': 'grant-chatgpt', 'name': 'ChatGPT', 'connectedAt': now},
        {'id': 'grant-claude', 'name': 'Claude', 'connectedAt': DateTime(2026, 11, 4, 15).millisecondsSinceEpoch},
      ]},
    });
  });

  Future<void> show(WidgetTester tester, Widget page) async {
    windowOf(tester, const Size(1100, 1400));
    await tester.pumpWidget(themed(Scaffold(body: page)));
    await tester.pumpAndSettle();
  }

  Future<void> connectAi(WidgetTester tester) => show(tester, WebConnectAiPage(client: space.client,
    onSavedChats: () => savedChats++, opener: (address) async {
      opened.add(address);
      return true;
    }));

  Finder inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
  Finder on(String row, String text) => find.descendant(of: find.widgetWithText(ListTile, row), matching: find.text(text));

  group('Connect your AI', () {
    testWidgets('shows the computers, Saved chats, Get the plugin, the address to copy and each app', (tester) async {
      final copied = catchCopies(tester);
      await connectAi(tester);
      expect(find.text('Let your AI read your notes, health and places, and add notes when you ask.'), findsOneWidget);
      expect([find.text('Claude Code and Codex'), find.text('Claude, ChatGPT and other AI apps'),
        on('Work Mac', 'Plugin · no chat saved yet'), find.text('mcp.example.com'), on('Claude', 'Connected Nov 4'),
        find.text('ChatGPT')], everyElement(findsOneWidget));
      // Phones show on Account.
      expect(find.text('iPhone'), findsNothing);
      await press(tester, find.widgetWithText(TextButton, 'Copy'));
      expect(copied, [connector]);
      await press(tester, find.text('Saved chats'));
      expect(savedChats, 1);
      await press(tester, find.text('Get the plugin'));
      expect(opened, [Uri.parse('https://relayeverything.com/connections/claude-code/')]);
      expect(find.text('Disconnect on your Relay Everything page'), findsNothing);
    });

    testWidgets('disconnects an app only after a confirm, and shows a refusal', (tester) async {
      await connectAi(tester);
      final claude = on('Claude', 'Disconnect');
      await press(tester, claude);
      expect(find.text('Disconnect Claude?'), findsOneWidget);
      await press(tester, inDialog('Cancel'));
      expect(space.count('POST ai-apps-disconnect'), 0);
      space.answers['POST ai-apps-disconnect'] = (_) => refusal(502, 'Claude could not be disconnected. Try again.');
      await press(tester, claude);
      await press(tester, inDialog('Disconnect'));
      expect(find.text('Claude could not be disconnected. Try again.'), findsOneWidget);
      space.answers.addAll({
        'POST ai-apps-disconnect': (_) => {'id': 'grant-claude'},
        'GET ai-apps': (_) => {'address': connector, 'apps': [{'id': 'grant-chatgpt', 'name': 'ChatGPT', 'connectedAt': now}]},
      });
      await press(tester, claude);
      await press(tester, inDialog('Disconnect'));
      expect(space.sent('POST ai-apps-disconnect').last, {'id': 'grant-claude'});
      expect([find.text('Claude'), find.text('ChatGPT')], [findsNothing, findsOneWidget]);
    });

    testWidgets('disconnects a computer after a confirm', (tester) async {
      await connectAi(tester);
      await press(tester, on('Work Mac', 'Disconnect'));
      expect(find.text('Disconnect Work Mac?'), findsOneWidget);
      space.answers['POST devices/off'] = (_) {
        connections = {...connections, 'devices': [(connections['devices']! as List).first]};
        return {'id': 'd4', 'revokedAt': now};
      };
      await press(tester, inDialog('Disconnect'));
      expect(space.sent('POST devices/off'), [{'id': 'd4'}]);
      expect(find.text('Work Mac'), findsNothing);
    });

    testWidgets('says when the AI connector is not set up, and still lists the computers', (tester) async {
      space.answers['GET ai-apps'] = (_) => refusal(503, 'Not set up.');
      await connectAi(tester);
      expect([find.text('The AI connector is not set up on this server.'), find.text('Work Mac')],
        everyElement(findsOneWidget));
      expect(find.text('Copy'), findsNothing);
    });
  });

  group('Email notes', () {
    testWidgets('shows both addresses with Copy, the warning, and makes a new address after a confirm', (tester) async {
      final copied = catchCopies(tester);
      await show(tester, WebEmailNotesPage(client: space.client));
      expect([find.text('Send or forward an email, and it becomes a note, with its files.'), find.text('From you@example.com'),
        find.text('notes@in.example.com'), find.text('From any address'), find.text('notes-k7q2m9xwab@in.example.com'),
        find.text('Email is not sealed on the way. Do not send health or location details this way.')],
        everyElement(findsOneWidget));
      await press(tester, on('notes@in.example.com', 'Copy'));
      expect(copied, ['notes@in.example.com']);
      await press(tester, find.text('New address'));
      await press(tester, inDialog('Cancel'));
      expect(space.count('POST inbox/address'), 0);
      space.answers['POST inbox/address'] = (_) {
        connections = {...connections, 'notesAddress': 'notes-zz2233ffgg@in.example.com'};
        return {'email': {'on': true, 'address': 'notes-zz2233ffgg@in.example.com'}};
      };
      await press(tester, find.text('New address'));
      await press(tester, inDialog('New address'));
      expect(space.count('POST inbox/address'), 1);
      expect(find.text('notes-zz2233ffgg@in.example.com'), findsOneWidget);
    });

    testWidgets('says when the server takes no email', (tester) async {
      connections = {'email': 'you@example.com'};
      await show(tester, WebEmailNotesPage(client: space.client));
      expect(find.text('Email notes are not set up on this server.'), findsOneWidget);
      expect(find.text('New address'), findsNothing);
    });
  });
}
