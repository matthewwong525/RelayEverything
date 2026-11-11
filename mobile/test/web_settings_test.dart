import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/web/settings_dialog.dart';

import 'web_space_fixture.dart';

// Fixture answers from the React page's tests (Webhooks, Devices), with made-up names and addresses.
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

const madeKey = 'rek_MadeUpKeyForTestsOnly0000000000000000000';

void main() {
  late FakeSpace space;
  late TinyRelay relay;
  late List<Map<String, Object?>> devices;
  late Map<String, Object?> connections;

  setUp(() {
    space = FakeSpace();
    relay = TinyRelay();
    devices = [
      {'id': 'd1', 'name': 'iPhone', 'reaches': 'phone', 'createdAt': now, 'revokedAt': null},
      {'id': 'd4', 'name': 'Work Mac', 'reaches': 'agent', 'createdAt': now, 'revokedAt': null},
      {'id': 'k1', 'name': 'Backup', 'reaches': 'api', 'createdAt': now, 'revokedAt': null},
      {'id': 'k2', 'name': 'Old script', 'reaches': 'api', 'createdAt': now - 3 * day, 'revokedAt': now - day},
    ];
    final year = DateTime.now().year;
    connections = {
      'email': 'you@example.com',
      'devices': [
        {'id': 'd1', 'name': 'iPhone', 'kind': 'phone', 'since': DateTime(year, 11, 2).millisecondsSinceEpoch},
        {'id': 'd5', 'name': 'Pixel', 'kind': 'phone', 'since': DateTime(year, 10, 14).millisecondsSinceEpoch},
        {'id': 'd4', 'name': 'Work Mac', 'kind': 'computer', 'since': now, 'lastChatAt': now},
      ],
      'aiApps': [{'name': 'Claude', 'connectedAt': now}],
      'webhooks': [{'name': 'Database 1'}, {'name': 'Database 2'}],
      'notesAddress': 'notes-k7q2m9xwab@in.example.com',
      'sharedAddress': 'notes@in.example.com',
    };
    space.answers.addAll({
      'GET account': (_) => {'email': 'you@example.com'},
      'GET connections': (_) => connections,
      'GET devices': (_) => {'devices': devices},
      'GET webhooks': (_) => {'webhooks': [working, failing, paused], 'kinds': kinds},
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

  testWidgets('lists Account and Appearance down the left, as the phone does, opens on Account, and closing leaves the page '
      'under it', (tester) async {
    await open(tester);
    expect(SettingsPage.listed, [SettingsPage.account, SettingsPage.appearance]);
    for (final page in SettingsPage.values) {
      expect(find.byKey(ValueKey('settings-${page.name}')), SettingsPage.listed.contains(page) ? findsOneWidget : findsNothing,
        reason: page.title);
    }
    for (final gone in ['Devices', 'AI apps', 'Email notes']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('you@example.com'), findsOneWidget);
    await press(tester, find.byTooltip('Close'));
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('The open note'), findsOneWidget);
    expect(relay.calls, isEmpty);
  });

  test('an address part opens its page: the old devices opens Account; AI apps and Email notes are no page of Settings', () {
    expect([for (final part in ['account', 'appearance', 'api-keys', '/webhooks', 'devices'])
      SettingsPage.ofPart(part)], [SettingsPage.account, SettingsPage.appearance, SettingsPage.apiKeys, SettingsPage.webhooks,
      SettingsPage.account]);
    expect([for (final part in ['ai-apps', 'email-notes', 'chats', '']) SettingsPage.ofPart(part)], everyElement(isNull));
    expect([SettingsPage.apiKeys.inList, SettingsPage.webhooks.inList], [SettingsPage.account, SettingsPage.account]);
  });

  testWidgets('Account shows the email with Sign out, the phones, Advanced and Delete my account, in that order',
      (tester) async {
    await open(tester);
    final tops = [for (final text in ['you@example.com', 'Phones', 'Advanced', 'Delete my account'])
      tester.getTopLeft(find.text(text)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.descendant(of: find.widgetWithText(ListTile, 'you@example.com'), matching: find.text('Signed in')),
      findsOneWidget);
    expect([find.text('iPhone'), find.text('Pixel')], everyElement(findsOneWidget));
    expect(find.descendant(of: find.widgetWithText(ListTile, 'Pixel'), matching: find.text('Since Oct 14')), findsOneWidget);
    // Computers show in Connect your AI, and an API key on its own page.
    expect([find.text('Work Mac'), find.text('Backup')], everyElement(findsNothing));
    expect([find.text('API keys'), find.text('For your own scripts'), find.text('Webhooks'),
      find.text('Send a copy to your own server')], everyElement(findsOneWidget));
    expect(find.descendant(of: find.widgetWithText(ListTile, 'Webhooks'), matching: find.text('2')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsNWidgets(3));
  });

  testWidgets('Sign out beside the email closes Settings and signs out', (tester) async {
    await open(tester);
    await press(tester, find.descendant(of: find.widgetWithText(ListTile, 'you@example.com'), matching: find.text('Sign out')));
    expect(find.byType(Dialog), findsNothing);
    expect(relay.calls, ['disconnect']);
  });

  testWidgets('Sign out beside a phone asks first, then signs out that phone alone', (tester) async {
    await open(tester);
    final pixel = find.descendant(of: find.widgetWithText(ListTile, 'Pixel'), matching: find.text('Sign out'));
    await press(tester, pixel);
    expect(find.text('Sign out Pixel?'), findsOneWidget);
    await press(tester, inDialog('Cancel'));
    expect(space.count('POST devices/off'), 0);
    space.answers['POST devices/off'] = (body) {
      connections = {...connections, 'devices': [for (final device in connections['devices']! as List)
        if ((device as Map)['id'] != 'd5') device]};
      return {'id': 'd5', 'revokedAt': now};
    };
    await press(tester, pixel);
    await press(tester, find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Sign out')));
    expect(space.sent('POST devices/off'), [{'id': 'd5'}]);
    expect([find.text('Pixel'), find.text('iPhone')], [findsNothing, findsOneWidget]);
    expect(relay.calls, isEmpty);
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

  testWidgets('API keys opens from Advanced, lists only API keys with Turn off, and Account goes back', (tester) async {
    await open(tester);
    await press(tester, find.text('API keys'));
    expect(find.text('For your own scripts. One key can serve many scripts.'), findsOneWidget);
    expect([find.text('Backup'), find.text('Old script')], everyElement(findsOneWidget));
    expect([find.text('iPhone'), find.text('Work Mac')], everyElement(findsNothing));
    // The list's row stays on Account.
    expect(tester.widget<ListTile>(find.byKey(const ValueKey('settings-account'))).selected, isTrue);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Turn off'), findsOneWidget);
    space.answers['POST devices/off'] = (body) {
      devices = [for (final device in devices) device['id'] == 'k1' ? {...device, 'revokedAt': now} : device];
      return {'id': 'k1', 'revokedAt': now};
    };
    await press(tester, find.text('Turn off'));
    expect(find.text('Turn off Backup?'), findsOneWidget);
    await press(tester, inDialog('Turn off'));
    expect(space.sent('POST devices/off'), [{'id': 'k1'}]);
    expect([find.text('Turn off'), find.text('Off')], [findsNothing, findsNWidgets(2)]);
    await press(tester, find.widgetWithText(TextButton, 'Account'));
    expect(find.text('you@example.com'), findsOneWidget);
  });

  testWidgets('Add an API key asks only a name, shows the key once with the example call and no QR code, or says why not',
      (tester) async {
    final copied = catchCopies(tester);
    await open(tester, first: SettingsPage.apiKeys);
    await press(tester, find.text('Add an API key'));
    expect(find.byWidgetPredicate((widget) => widget is SegmentedButton), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), '  Nightly  ');
    space.answers['POST devices'] = (_) => refusal(400, 'The name is too long.');
    await press(tester, find.text('Make the key'));
    expect(find.text('The name is too long.'), findsOneWidget);
    space.answers['POST devices'] = (body) => {'id': 'k9', 'name': 'Nightly', 'reaches': 'api', 'key': madeKey,
      'api': 'https://mcp.example.com/v1'};
    await press(tester, find.text('Make the key'));
    expect(space.sent('POST devices').last, {'name': 'Nightly', 'reaches': 'api'});
    expect(find.text('Use Nightly'), findsOneWidget);
    expect(find.text(madeKey), findsOneWidget);
    expect(find.text('curl -H "Authorization: Bearer $madeKey" https://mcp.example.com/v1/me'), findsOneWidget);
    await press(tester, find.text('Copy the key'));
    expect(copied, [madeKey]);
    await press(tester, find.text('Done'));
    // The list reads again, and the key is gone for good.
    expect(space.count('GET devices'), 2);
    expect(find.textContaining(madeKey), findsNothing);
  });

  testWidgets('Add an API key with no name calls it Script, and the list reads again when Escape closes it',
      (tester) async {
    space.answers['POST devices'] = (body) {
      devices = [...devices, {'id': 'k9', 'name': 'Script', 'reaches': 'api', 'createdAt': now, 'revokedAt': null}];
      return {'id': 'k9', 'name': 'Script', 'reaches': 'api', 'key': madeKey, 'api': null};
    };
    await open(tester, first: SettingsPage.apiKeys);
    await press(tester, find.text('Add an API key'));
    await press(tester, find.text('Make the key'));
    expect(space.sent('POST devices'), [{'name': 'Script', 'reaches': 'api'}]);
    expect(find.text('curl -H "Authorization: Bearer $madeKey" <your-relay-server>/v1/me'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(space.count('GET devices'), 2);
    expect(find.text('Script'), findsOneWidget);
  });

  testWidgets('Webhooks opens from Advanced, with Account to go back', (tester) async {
    await open(tester);
    await press(tester, find.text('Webhooks'));
    expect(onCard('Database 1', 'Working'), findsOneWidget);
    await press(tester, find.widgetWithText(TextButton, 'Account'));
    expect(find.text('you@example.com'), findsOneWidget);
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

  testWidgets('Appearance picks System, Light or Dark', (tester) async {
    await open(tester, first: SettingsPage.appearance);
    await press(tester, find.text('Dark'));
    expect(relay.calls, ['appearance dark']);
    expect(relay.settings.appearance, Appearance.dark);
  });

  testWidgets('in a narrow window Settings fills it, shows the list first, and goes back to it', (tester) async {
    await open(tester, size: const Size(390, 844));
    expect(find.text('you@example.com'), findsNothing);
    await pick(tester, SettingsPage.appearance);
    expect(find.text('Dark'), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-account')), findsNothing);
    await press(tester, find.byTooltip('Back'));
    await pick(tester, SettingsPage.account);
    expect(find.text('you@example.com'), findsOneWidget);
    await press(tester, find.text('API keys'));
    expect(find.text('Backup'), findsOneWidget);
  });

  testWidgets('a page that could not load says why and tries again', (tester) async {
    space.answers['GET devices'] = (_) => refusal(500, 'The server had a problem.');
    await open(tester, first: SettingsPage.apiKeys);
    expect(find.text('API keys could not be loaded. The server had a problem.'), findsOneWidget);
    space.answers['GET devices'] = (_) => {'devices': devices};
    await press(tester, find.text('Try again'));
    expect(find.text('Backup'), findsOneWidget);
  });
}
