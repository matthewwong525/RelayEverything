import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/web/settings_dialog.dart';

import 'web_space_fixture.dart';

// Fixture answers from the React page's tests (Webhooks, AiCard, Inbox, Devices), with made-up names and addresses.
final now = DateTime.now().millisecondsSinceEpoch;
const day = 86400000;

Map<String, Object?> hook(String id, [Map<String, Object?> more = const {}]) => {'id': id, 'name': 'Database $id',
  'url': 'https://db$id.example.com/relay', 'kinds': ['notes'], 'state': 'working', 'waiting': 0, 'lastStatus': null,
  'lastError': null, 'lastSentAt': null, 'nextTryAt': null, 'failingSince': null, 'createdAt': now, 'attempts': [], ...more};

final working = hook('1', {'kinds': ['notes', 'health', 'locations', 'calendar'], 'waiting': 3, 'lastStatus': 200, 'lastSentAt': now});
final failing = hook('2', {'state': 'failing', 'waiting': 12, 'lastStatus': 503, 'lastError': 'Answered 503.',
  'failingSince': now, 'nextTryAt': now + day});
final paused = hook('3', {'state': 'paused'});

const kinds = [
  {'id': 'notes', 'label': 'Notes', 'detail': 'with their words, recording and place', 'always': true, 'sensitive': false},
  {'id': 'health', 'label': 'Health', 'detail': 'steps, heart rate, sleep, weight and more', 'always': false, 'sensitive': true},
  {'id': 'locations', 'label': 'Location history', 'detail': '', 'always': false, 'sensitive': true},
  {'id': 'calendar', 'label': 'Calendar', 'detail': 'new, changed and removed events', 'always': false, 'sensitive': true},
];

const inboxOn = {'on': true, 'address': 'notes-k7q2m9xwab@in.example.com', 'shared': 'notes@in.example.com'};
const connector = 'https://relay-mcp.example.com/mcp';
const madeKey = 'rek_MadeUpKeyForTestsOnly0000000000000000000';
const madeQr = '{"relay":1,"server":"https://relay.example.com","key":"$madeKey"}';

void main() {
  late FakeSpace space;
  late TinyRelay relay;
  late List<Map<String, Object?>> devices;

  setUp(() {
    space = FakeSpace();
    relay = TinyRelay();
    devices = [
      {'id': 'd1', 'name': 'iPhone', 'reaches': 'phone', 'createdAt': now, 'revokedAt': null},
      {'id': 'd2', 'name': 'Laptop', 'reaches': 'chats', 'createdAt': now - 3 * day, 'revokedAt': now - day},
      // A keyless way in that an older server may list: it has no key to turn off.
      {'id': 'd3', 'name': 'Web', 'reaches': 'inbox', 'createdAt': now, 'revokedAt': null},
    ];
    space.answers.addAll({
      'GET account': (_) => {'email': 'you@example.com'},
      'GET inbox': (_) => {'email': inboxOn},
      'GET devices': (_) => {'devices': devices},
      'GET webhooks': (_) => {'webhooks': [working, failing, paused], 'kinds': kinds},
      'GET ai-apps': (_) => {'address': connector, 'apps': [
        {'id': 'grant-chatgpt', 'name': 'ChatGPT', 'connectedAt': now},
        {'id': 'grant-claude', 'name': 'Claude', 'connectedAt': DateTime.utc(2026, 11, 4, 15).millisecondsSinceEpoch},
      ]},
    });
  });

  Future<void> open(WidgetTester tester, {SettingsPage first = SettingsPage.account, Size size = const Size(1280, 900)}) async {
    windowOf(tester, size);
    await tester.pumpWidget(themed(Builder(builder: (context) => Scaffold(body: Center(child: TextButton(
      onPressed: () => showSettingsDialog(context, relay: relay, client: space.client, first: first,
        opener: (_) async => true),
      child: const Text('The open note')))))));
    await tester.tap(find.text('The open note'));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, SettingsPage page) => press(tester, find.byKey(ValueKey('settings-${page.name}')));

  Finder inDialog(String text) => find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
  Finder card(String name) => find.ancestor(of: find.text(name), matching: find.byType(Card));
  Finder onCard(String name, String text) => find.descendant(of: card(name), matching: find.text(text));
  Finder matching(RegExp pattern) => find.byWidgetPredicate((widget) => widget is Text && pattern.hasMatch(widget.data ?? ''));

  testWidgets('lists its pages down the left, opens on Account, and closing leaves the page under it', (tester) async {
    await open(tester);
    for (final page in SettingsPage.values) {
      expect(find.byKey(ValueKey('settings-${page.name}')), findsOneWidget, reason: page.title);
    }
    expect(find.text('you@example.com'), findsOneWidget);
    await press(tester, find.byTooltip('Close'));
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('The open note'), findsOneWidget);
    expect(relay.calls, isEmpty);
  });

  testWidgets('Sign out closes Settings and signs out', (tester) async {
    await open(tester);
    await press(tester, find.text('Sign out'));
    expect(find.byType(Dialog), findsNothing);
    expect(relay.calls, ['disconnect']);
  });

  testWidgets('Delete my account needs the email typed again, shows a refusal, then deletes and signs out', (tester) async {
    await open(tester);
    await press(tester, find.text('Delete my account'));
    FilledButton deleteButton() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Delete everything'));
    expect(deleteButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'someone@example.com');
    await tester.pump();
    expect(deleteButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), ' You@Example.com ');
    await tester.pump();
    space.answers['POST account-delete'] = (_) => refusal(400, "Type your account's email to confirm.");
    await press(tester, find.text('Delete everything'));
    expect(find.text("Type your account's email to confirm."), findsOneWidget);
    expect(relay.calls, isEmpty);
    space.answers['POST account-delete'] = (_) => {'deleted': true};
    await press(tester, find.text('Delete everything'));
    expect(space.sent('POST account-delete').last, {'email': 'You@Example.com'});
    expect(find.byType(Dialog), findsNothing);
    expect(relay.calls, ['disconnect']);
  });

  testWidgets('Devices lists each key with Turn off, and leaves out a keyless device', (tester) async {
    await open(tester, first: SettingsPage.devices);
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.text('Laptop'), findsOneWidget);
    expect(find.text('Web'), findsNothing);
    expect(find.textContaining('Notes, health, places, calendar and photos · added'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);
    space.answers['POST devices/off'] = (body) {
      devices = [{...devices[0], 'revokedAt': now}, devices[1]];
      return {'id': 'd1', 'revokedAt': now};
    };
    await press(tester, find.text('Turn off'));
    expect(find.text('Turn off iPhone?'), findsOneWidget);
    await press(tester, inDialog('Turn off'));
    expect(space.sent('POST devices/off'), [{'id': 'd1'}]);
    expect(find.text('Turn off'), findsNothing);
    expect(find.text('Off'), findsNWidgets(2));
  });

  testWidgets('Add a device shows the new key once, as a QR code and as text to copy', (tester) async {
    final copied = catchCopies(tester);
    space.answers['POST devices'] = (body) =>
      {'id': 'd9', 'name': 'Phone', 'reaches': 'phone', 'key': madeKey, 'qr': madeQr, 'api': null};
    await open(tester, first: SettingsPage.devices);
    await press(tester, find.text('Add a device'));
    expect(find.byType(QrImageView), findsNothing);
    await press(tester, find.text('Make the key'));
    expect(space.sent('POST devices'), [{'name': 'Phone', 'reaches': 'phone'}]);
    expect(find.text('Connect Phone'), findsOneWidget);
    expect(tester.widget<QrImageView>(find.byType(QrImageView)).semanticsLabel, 'QR code for Phone');
    expect(find.text(madeQr), findsOneWidget);
    await press(tester, find.text('Copy the code'));
    expect(copied, [madeQr]);
    expect(find.text('Copied'), findsOneWidget);
    await press(tester, find.text('Done'));
    // The list reads again, and the key is gone for good.
    expect(space.count('GET devices'), 2);
    expect(find.byType(QrImageView), findsNothing);
    expect(find.textContaining(madeKey), findsNothing);
    await press(tester, find.text('Add a device'));
    expect(find.text('Make the key'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
    await press(tester, find.text('Cancel'));
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('a new device shows in the list even when Escape closes Add a device', (tester) async {
    space.answers['POST devices'] = (body) {
      devices = [...devices, {'id': 'd9', 'name': 'Pixel', 'reaches': 'phone', 'createdAt': now, 'revokedAt': null}];
      return {'id': 'd9', 'name': 'Pixel', 'reaches': 'phone', 'key': madeKey, 'qr': madeQr, 'api': null};
    };
    await open(tester, first: SettingsPage.devices);
    await press(tester, find.text('Add a device'));
    await tester.enterText(find.byType(TextField), 'Pixel');
    await press(tester, find.text('Make the key'));
    expect(find.text('Connect Pixel'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(space.count('GET devices'), 2);
    expect(find.text('Pixel'), findsOneWidget);
  });

  testWidgets('Add a device makes an API key with its name, the example call and no QR code, or says why not',
      (tester) async {
    await open(tester, first: SettingsPage.devices);
    await press(tester, find.text('Add a device'));
    await press(tester, find.text('API key'));
    await tester.enterText(find.byType(TextField), '  Backup  ');
    space.answers['POST devices'] = (_) => refusal(400, 'The name is too long.');
    await press(tester, find.text('Make the key'));
    expect(find.text('The name is too long.'), findsOneWidget);
    space.answers['POST devices'] = (body) => {'id': 'd9', 'name': 'Backup', 'reaches': 'api', 'key': madeKey,
      'qr': madeQr, 'api': 'https://relay-mcp.example.com/v1'};
    await press(tester, find.text('Make the key'));
    expect(space.sent('POST devices').last, {'name': 'Backup', 'reaches': 'api'});
    expect(find.text('Connect Backup'), findsOneWidget);
    expect(find.text(madeKey), findsOneWidget);
    expect(find.text('curl -H "Authorization: Bearer $madeKey" https://relay-mcp.example.com/v1/me'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets("Webhooks shows each one's state, what it takes, what waits and its last answer", (tester) async {
    await open(tester, first: SettingsPage.webhooks);
    expect(onCard('Database 1', 'Working'), findsOneWidget);
    expect(matching(RegExp(r'^db1\.example\.com · notes, health, location history, calendar · 3 waiting · last sent .+ · '
      r'last answer: answered 200$')), findsOneWidget);
    expect(matching(RegExp(r'12 waiting · next try .+ · failing since .+ · last answer: Answered 503\.$')), findsOneWidget);
    expect(onCard('Database 2', 'Failing'), findsOneWidget);
    expect(matching(RegExp(r'^db3\.example\.com · notes · nothing sent yet$')), findsOneWidget);
    expect(onCard('Database 3', 'Resume'), findsOneWidget);
    expect(onCard('Database 2', 'Try again now'), findsOneWidget);
  });

  testWidgets('Webhooks adds one with the kinds ticked, shows its secret once, and says why not', (tester) async {
    final copied = catchCopies(tester);
    await open(tester, first: SettingsPage.webhooks);
    await press(tester, find.text('Add a webhook'));
    expect(find.text('Notes always go, with their words, recording and place.'), findsOneWidget);
    expect(find.text('Health, location history and calendar are sensitive. Tick each only for a database you control.'),
      findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
    await press(tester, find.textContaining('Health:'));
    await press(tester, find.text('Location history'));
    await press(tester, find.text('Location history'));
    space.answers['POST webhooks'] = (_) => refusal(400, "The address can't be this computer or a private network.");
    await press(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(find.text("The address can't be this computer or a private network."), findsOneWidget);
    space.answers['POST webhooks'] = (_) => {'webhook': hook('9', {'name': 'My database'}), 'secret': 'whsec_example'};
    await press(tester, find.widgetWithText(FilledButton, 'Add'));
    expect(space.sent('POST webhooks').last, {'name': 'My database', 'url': 'https://db.example.com/relay', 'kinds': ['health']});
    expect(find.text('Webhook added'), findsOneWidget);
    expect(find.text('whsec_example'), findsOneWidget);
    await press(tester, find.text('Copy the secret'));
    expect(copied, ['whsec_example']);
    await press(tester, find.text('Done'));
    expect(find.text('whsec_example'), findsNothing);
    expect(space.count('GET webhooks'), 2);
    await press(tester, find.text('Add a webhook'));
    expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Address')).controller!.text, 'https://');
  });

  testWidgets('Webhooks sends a test and says what came back, or why nothing did', (tester) async {
    await open(tester, first: SettingsPage.webhooks);
    for (final (answer, line) in [
      ({'status': 200, 'ms': 180, 'error': null}, 'Answered 200 in 180 ms.'),
      ({'status': 302, 'ms': 1500, 'error': 'Answered with a redirect, which Relay Everything does not follow.'},
        'Answered 302 in 1.5 s. Answered with a redirect, which Relay Everything does not follow.'),
      ({'status': null, 'ms': 15000, 'error': 'No answer in 15 seconds.'}, 'No answer: No answer in 15 seconds.'),
    ]) {
      space.answers['POST webhooks/test'] = (_) => answer;
      await press(tester, onCard('Database 1', 'Send a test'));
      expect(onCard('Database 1', line), findsOneWidget);
    }
    space.answers['POST webhooks/test'] = (_) => refusal(500, 'The test could not run.');
    await press(tester, onCard('Database 1', 'Send a test'));
    expect(onCard('Database 1', 'The test could not run.'), findsOneWidget);
    expect(space.sent('POST webhooks/test'), List.filled(4, {'id': '1'}));
  });

  testWidgets('Webhooks tries again, pauses, resumes, sends past data, changes what it takes, makes a secret and removes',
      (tester) async {
    space.answers.addAll({
      'POST webhooks/retry': (_) => {'webhook': {...failing, 'state': 'working'}},
      'POST webhooks/update': (body) => {'webhook': working},
      'POST webhooks/resend': (_) => {'webhook': {...working, 'state': 'backfilling'}},
      'POST webhooks/secret': (_) => {'secret': 'whsec_new'},
      'POST webhooks/remove': (_) => {'removed': true},
    });
    await open(tester, first: SettingsPage.webhooks);
    await press(tester, onCard('Database 2', 'Try again now'));
    expect(space.sent('POST webhooks/retry'), [{'id': '2'}]);
    await press(tester, onCard('Database 1', 'Pause'));
    await press(tester, onCard('Database 3', 'Resume'));
    expect(space.sent('POST webhooks/update'), [{'id': '1', 'active': false}, {'id': '3', 'active': true}]);

    await press(tester, onCard('Database 1', 'Send past data'));
    await press(tester, find.text('Send'));
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    expect(space.sent('POST webhooks/resend'),
      [{'id': '1', 'since': DateTime(weekAgo.year, weekAgo.month, weekAgo.day).millisecondsSinceEpoch}]);

    await press(tester, onCard('Database 1', 'What it takes'));
    expect(find.text('What Database 1 takes'), findsOneWidget);
    await press(tester, find.textContaining('Calendar:'));
    await press(tester, find.text('Save'));
    expect(space.sent('POST webhooks/update').last, {'id': '1', 'kinds': ['health', 'locations']});

    await press(tester, onCard('Database 1', 'New secret'));
    expect(find.text('Make a new secret for Database 1?'), findsOneWidget);
    await press(tester, inDialog('New secret'));
    expect(find.text('whsec_new'), findsOneWidget);
    await press(tester, find.text('Done'));
    expect(find.text('whsec_new'), findsNothing);

    await press(tester, onCard('Database 3', 'Remove'));
    await press(tester, inDialog('Remove'));
    expect(space.sent('POST webhooks/remove'), [{'id': '3'}]);
  });

  testWidgets('AI apps shows the address to copy and each app, and disconnects one only after a confirm', (tester) async {
    final copied = catchCopies(tester);
    await open(tester, first: SettingsPage.aiApps);
    expect(find.text(connector), findsOneWidget);
    expect(find.text('Connected apps · 2 connected'), findsOneWidget);
    expect(find.text('Connected Nov 4, ${DateTime.utc(2026, 11, 4, 15).toLocal().hour.toString().padLeft(2, '0')}:00'),
      findsOneWidget);
    await press(tester, find.text('Copy'));
    expect(copied, [connector]);
    final claude = find.descendant(of: find.widgetWithText(ListTile, 'Claude'), matching: find.text('Disconnect'));
    await press(tester, claude);
    expect(find.text('Disconnect Claude?'), findsOneWidget);
    await press(tester, find.text('Cancel'));
    expect(space.count('POST ai-apps-disconnect'), 0);
    space.answers['POST ai-apps-disconnect'] = (_) => refusal(502, 'Claude could not be disconnected. Try again.');
    await press(tester, claude);
    await press(tester, inDialog('Disconnect'));
    expect(find.text('Claude could not be disconnected. Try again.'), findsOneWidget);
    expect(find.text('Claude'), findsOneWidget);
    space.answers.addAll({
      'POST ai-apps-disconnect': (_) => {'id': 'grant-claude'},
      'GET ai-apps': (_) => {'address': connector, 'apps': [{'id': 'grant-chatgpt', 'name': 'ChatGPT', 'connectedAt': now}]},
    });
    await press(tester, claude);
    await press(tester, inDialog('Disconnect'));
    expect(space.sent('POST ai-apps-disconnect').last, {'id': 'grant-claude'});
    expect(find.text('Connected apps · 1 connected'), findsOneWidget);
    expect(find.text('Claude'), findsNothing);
  });

  testWidgets('AI apps says when the connector is not set up', (tester) async {
    space.answers['GET ai-apps'] = (_) => refusal(503, 'Not set up.');
    await open(tester, first: SettingsPage.aiApps);
    expect(find.text('The AI connector is not set up on this server.'), findsOneWidget);
  });

  testWidgets('Email notes shows the address, the shared address and the warning, and makes a new address after a confirm',
      (tester) async {
    await open(tester, first: SettingsPage.emailNotes);
    expect(find.text('notes-k7q2m9xwab@in.example.com'), findsOneWidget);
    expect(find.text('Anything sent here becomes a note.'), findsOneWidget);
    expect(find.text('You can also write to notes@in.example.com from your sign-in email.'), findsOneWidget);
    expect(find.text('Email is not sealed on the way. Do not send health or location details this way.'), findsOneWidget);
    await press(tester, find.text('New address'));
    await press(tester, find.text('Cancel'));
    expect(space.count('POST inbox/address'), 0);
    space.answers.addAll({
      'POST inbox/address': (_) => {'email': {...inboxOn, 'address': 'notes-zz2233ffgg@in.example.com'}},
      'GET inbox': (_) => {'email': {...inboxOn, 'address': 'notes-zz2233ffgg@in.example.com'}},
    });
    await press(tester, find.text('New address'));
    await press(tester, inDialog('New address'));
    expect(space.count('POST inbox/address'), 1);
    expect(find.text('notes-zz2233ffgg@in.example.com'), findsOneWidget);
  });

  for (final (name, answer) in [('a 503', (_) => refusal(503, 'No mail here.')), ('email off', (_) => {'email': {'on': false,
      'address': null, 'shared': null}})]) {
    testWidgets('$name hides Email notes from the list', (tester) async {
      space.answers['GET inbox'] = answer;
      await open(tester, first: SettingsPage.emailNotes);
      expect(find.byKey(const ValueKey('settings-emailNotes')), findsNothing);
      expect(find.text('Email notes'), findsNothing);
      // The page asked for falls back to Account.
      expect(find.text('you@example.com'), findsOneWidget);
    });
  }

  testWidgets('Appearance picks System, Light or Dark', (tester) async {
    await open(tester, first: SettingsPage.appearance);
    await press(tester, find.text('Dark'));
    expect(relay.calls, ['appearance dark']);
    expect(relay.settings.appearance, Appearance.dark);
  });

  testWidgets('in a narrow window Settings fills it, shows the list first, and goes back to it', (tester) async {
    await open(tester, size: const Size(390, 844));
    expect(find.text('you@example.com'), findsNothing);
    await pick(tester, SettingsPage.devices);
    expect(find.text('iPhone'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-account')), findsNothing);
    await press(tester, find.byTooltip('Back'));
    await pick(tester, SettingsPage.account);
    expect(find.text('you@example.com'), findsOneWidget);
  });

  testWidgets('a page that could not load says why and tries again', (tester) async {
    space.answers['GET devices'] = (_) => refusal(500, 'The server had a problem.');
    await open(tester, first: SettingsPage.devices);
    expect(find.text('Devices could not be loaded. The server had a problem.'), findsOneWidget);
    space.answers['GET devices'] = (_) => {'devices': devices};
    await press(tester, find.text('Try again'));
    expect(find.text('iPhone'), findsOneWidget);
  });
}
