import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:relay_app/editor/web_note/cover.dart' show NoteCover;
import 'package:relay_app/editor/markdown.dart' show LineKind, plainText;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/screens/home.dart';
import 'package:relay_app/screens/note_bars.dart';
import 'package:relay_app/screens/note_blocks.dart';
import 'package:relay_app/screens/note_editor.dart';
import 'package:relay_app/screens/recently_deleted.dart' show keepLine;
import 'package:relay_app/screens/settings.dart';
import 'package:relay_app/screens/timeline.dart' show TimelineScreen;
import 'package:relay_app/web/chats.dart' show ChatsView;
import 'package:relay_app/web/connection_page.dart';
import 'package:relay_app/web/other_connections.dart';
import 'package:relay_app/web/settings_dialog.dart';
import 'package:relay_app/web/shell.dart';
import 'package:relay_app/web/web_relay.dart';

import 'fakes.dart' show FakePageView, FakePlayer, FakeWebNote;
import 'screens_test.dart' show FakeRelay, markdownOf, noteState, pageOf, tapWords, write;
import 'web_space_fixture.dart';

const wide = Size(1440, 900);
const middle = Size(900, 800);
const narrow = Size(390, 844);

void main() {
  late FakeRelay relay;
  late FakeSpace space;
  late StreamController<List<NewFile>> drops;
  final now = DateTime.now();

  setUp(() {
    PackageInfo.setMockInitialValues(appName: 'Relay Everything', packageName: 'com.relayeverything.app', version: '1.4.0',
      buildNumber: '1', buildSignature: '');
    relay = FakeRelay()
      ..platform = RelayPlatform.web
      ..connected = true
      ..settings = const Settings(sending: true)
      ..entries = [
        Entry(id: 'own', text: '# Groceries\nmilk and eggs', at: now, sent: true),
        Entry(id: 'voice', text: 'Call the dentist at 3', at: now.subtract(const Duration(hours: 1)), sent: true,
          recordings: const [EntryRecording(recording: 'https://relay.example.com/v1/notes/voice/recording', top: true)],
          from: 'iPhone'),
        Entry(id: 'link', text: 'Read https://example.com/post', at: now.subtract(const Duration(days: 1)), sent: true,
          from: 'Email'),
      ];
    space = FakeSpace();
    drops = StreamController<List<NewFile>>.broadcast();
  });

  tearDown(() => drops.close());

  Future<void> show(WidgetTester tester, Size size, {SettingsPage? settingsAt, WebPlace? placeAt}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
      home: WebShell(relay: relay, client: space.client, drops: drops.stream, opener: (_) async => true,
        settingsAt: settingsAt, placeAt: placeAt)));
    await tester.pumpAndSettle();
  }

  Future<void> resize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    await tester.pumpAndSettle();
  }

  /// Takes the page away and lets each wait end, so no timer stays after the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  Finder inSidebar(String text) => find.descendant(of: find.byType(Sidebar), matching: find.text(text));
  Finder inList(String text) => find.descendant(of: find.byType(NotesPane), matching: find.text(text));
  Finder sidebarCount(String title, int count) => find.descendant(
    of: find.ancestor(of: inSidebar(title), matching: find.byType(InkWell)).first, matching: find.text('$count'));

  Future<void> press(WidgetTester tester, List<LogicalKeyboardKey> held, LogicalKeyboardKey key) async {
    for (final down in held) {
      await tester.sendKeyDownEvent(down);
    }
    await tester.sendKeyEvent(key);
    for (final down in held.reversed) {
      await tester.sendKeyUpEvent(down);
    }
    await tester.pumpAndSettle();
  }

  /// *New note*'s custom actions for a screen reader: *Record a voice note* on the phone.
  List<int>? recordAction(WidgetTester tester) =>
    find.semantics.byLabel('New note').evaluate().single.getSemanticsData().customSemanticsActionIds;

  NoteEditorState editor(WidgetTester tester) => tester.state<NoteEditorState>(find.byType(NoteEditor));

  /// The key of the first recording's card in the note's page.
  String recordingKey(FakeWebNote page) => (page.loaded['files']! as Map).entries
    .firstWhere((file) => (file.value as Map)['kind'] == 'recording').key as String;

  group('three panes from 1000 px', () {
    testWidgets('the left bar opened at a middle width stops covering the note when a resize takes it away',
        (tester) async {
      for (final to in [wide, narrow]) {
        await show(tester, middle);
        tester.firstState<ScaffoldState>(find.byType(Scaffold)).openDrawer();
        await tester.pumpAndSettle();
        expect(NoteCover.open.value, 1);
        await resize(tester, to);
        expect(NoteCover.open.value, 0, reason: 'resized to $to');
        await finish(tester);
      }
    });

    testWidgets('Recently Deleted shows under Notes only while it holds a note, and opens its notes to read only',
        (tester) async {
      await show(tester, wide);
      expect(inSidebar('Recently Deleted'), findsNothing);
      await relay.deleteNote('voice');
      await tester.pumpAndSettle();
      expect(sidebarCount('Recently Deleted', 1), findsOneWidget);
      expect(tester.getTopLeft(inSidebar('Recently Deleted')).dy, greaterThan(tester.getTopLeft(inSidebar('Notes')).dy));
      await tester.tap(inSidebar('Recently Deleted'));
      await tester.pumpAndSettle();
      expect(find.byType(DeletedPane), findsOneWidget);
      expect(find.descendant(of: find.byType(DeletedPane), matching: find.text(keepLine)), findsOneWidget);
      expect(find.text('Pick a note to read it.'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(DeletedPane), matching: find.text('Call the dentist at 3')));
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'voice');
      expect(noteState(tester).readOnly, isTrue);
      // Recover All empties it, and the row leaves the left bar.
      await tester.tap(find.descendant(of: find.byType(DeletedPane), matching: find.byTooltip('More')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recover All'));
      await tester.pumpAndSettle();
      expect([relay.calls.last, inSidebar('Recently Deleted')], ['recover voice', findsNothing]);
      await finish(tester);
    });

    testWidgets('the left bar has one Notes row with its count, Other connections, and Settings at the bottom', (tester) async {
      await show(tester, wide);
      expect(inSidebar('Relay Everything'), findsOneWidget);
      expect(sidebarCount('Notes', 3), findsOneWidget);
      expect([inSidebar('Voice notes'), inSidebar('Shares')], everyElement(findsNothing));
      final rows = ['Other connections', 'Location', 'Health', 'Calendar', 'Photos', 'Connect your AI', 'Email notes'];
      for (final title in rows) {
        expect(inSidebar(title), findsOneWidget, reason: title);
      }
      final tops = [for (final title in rows) tester.getTopLeft(inSidebar(title)).dy];
      expect(tops, orderedEquals([...tops]..sort()));
      expect(inSidebar('AI chat transcripts'), findsNothing);
      expect(tester.getTopLeft(inSidebar('Settings')).dy, greaterThan(tester.getTopLeft(inSidebar('Email notes')).dy + 100),
        reason: 'Settings sits at the bottom of the left bar');
      await finish(tester);
    });

    testWidgets('the newest note opens in the right pane, with every tool in the top bar and nothing at the bottom',
        (tester) async {
      await show(tester, wide);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(editor(tester).id, 'own');
      expect(markdownOf(tester), startsWith('# Groceries'));
      for (final tool in ['New note', 'Text styles', 'Checklist', 'Table', 'Attach', 'Share', 'More']) {
        expect(find.byTooltip(tool), findsOneWidget, reason: tool);
      }
      expect(find.byType(SearchField), findsOneWidget);
      final bar = tester.getBottomLeft(find.byType(SearchField)).dy;
      expect(bar, lessThan(80), reason: 'the tools and search sit at the top');
      expect(find.byType(ReadingBar), findsNothing);
      expect(find.byType(FloatingToolBar), findsNothing);
      expect(find.byType(NewNoteButton), findsNothing);
      await finish(tester);
    });

    testWidgets("the open note's ⋯ offers Pin Note, which moves it under Pinned, and no Find in Note: the browser has its own",
        (tester) async {
      await show(tester, wide);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect([for (final item in tester.widgetList<MenuItemButton>(find.byType(MenuItemButton))) (item.child! as Text).data],
        ['Pin Note', 'Copy', 'Delete']);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Pin Note'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['pin own']);
      expect(inList('Pinned'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a click on a note opens it, and a filter above the list shows only its notes', (tester) async {
      await show(tester, wide);
      await tester.tap(inList('Call the dentist at 3'));
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'voice');
      Finder chip(String label) => find.descendant(of: find.byType(NotesPane), matching: find.widgetWithText(ChoiceChip, label));
      expect([chip('All 3'), chip('Voice 1'), chip('Photos and files 0')], everyElement(findsOneWidget));
      await tester.tap(chip('Voice 1'));
      await tester.pumpAndSettle();
      expect(inList('Call the dentist at 3'), findsOneWidget);
      expect([inList('Groceries'), inList('Read https://example.com/post')], everyElement(findsNothing));
      // A link alone is not a file.
      await tester.tap(chip('Photos and files 0'));
      await tester.pumpAndSettle();
      expect(inList('Read https://example.com/post'), findsNothing);
      await tester.tap(chip('All 3'));
      await tester.pumpAndSettle();
      expect(inList('Groceries'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a voice note with its recording shows the player, a plain line in the browser, and plays it', (tester) async {
      relay.entries = [Entry(id: 'voice', text: 'Call the dentist at 3', at: now, sent: true, from: 'iPhone',
        recordings: const [EntryRecording(recording: 'https://relay.example.com/v1/notes/voice/recording',
          length: Duration(seconds: 8), top: true)])];
      await show(tester, wide);
      expect(editor(tester).id, 'voice');
      final page = pageOf(tester);
      expect((page.loaded['head']! as Map)['above'], ['head:0']);
      expect([page.viewOf('head:0')!['kind'], page.viewOf('head:0')!['length'], page.viewOf('head:0')!['levels']],
        ['recording', 8000, isEmpty]);
      page.tap('head:0', 'play');
      await tester.pump();
      expect(relay.calls, contains('play https://relay.example.com/v1/notes/voice/recording'));
      expect(page.viewOf('head:0')!['playing'], isTrue);
      await finish(tester);
    });

    testWidgets('a recording from the phone shows Transcript in its card, Still on your phone until its sound comes, '
        'and the page shows no Record', (tester) async {
      relay.entries = [Entry(id: 'voice', text: '', at: now, sent: true, from: 'iPhone', recordings: const [
        EntryRecording(id: 'r1', recording: '', ready: false, transcript: 'Call the dentist at 3', length: Duration(seconds: 8),
          top: true)])];
      await show(tester, wide);
      final page = pageOf(tester);
      expect([page.viewOf('r1')!['ready'], page.viewOf('r1')!['status']], [false, 'words']);
      expect(find.byTooltip('Record'), findsNothing);
      relay
        ..entries = [Entry(id: 'voice', text: '', at: now, sent: true, from: 'iPhone', recordings: const [
          EntryRecording(id: 'r1', recording: 'https://relay.example.com/apps/relay/api/attachment?id=r1',
            transcript: 'Call the dentist at 3', length: Duration(seconds: 8), top: true)])]
        ..changed();
      await tester.pumpAndSettle();
      expect(page.viewOf('r1')!['ready'], isTrue);
      page.tap('r1', 'play');
      await tester.pump();
      expect(relay.calls, contains('play https://relay.example.com/apps/relay/api/attachment?id=r1'));
      await finish(tester);
    });

    testWidgets('search filters the notes as the person types', (tester) async {
      await show(tester, wide);
      await tester.enterText(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField)), 'DENTIST');
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(NotesPane), matching: find.textContaining('dentist', findRichText: true)),
        findsWidgets);
      expect(inList('Groceries'), findsNothing);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(inList('Groceries'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('an empty folder says how a note gets in it, not that a search found nothing', (tester) async {
      relay.entries = [];
      await show(tester, wide);
      expect(inList('No notes yet'), findsOneWidget);
      expect(inList('Click New note to write one.'), findsOneWidget);
      expect(find.textContaining('No notes with'), findsNothing);
      await tester.tap(find.descendant(of: find.byType(NotesPane), matching: find.widgetWithText(ChoiceChip, 'Voice 0')));
      await tester.pumpAndSettle();
      expect(inList('No voice notes yet'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a connection opens in place of the notes', (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Location'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionPage), findsOneWidget);
      expect(find.byType(NotesPane), findsNothing);
      await finish(tester);
    });

    testWidgets('coming back to the tab reads the notes changed elsewhere', (tester) async {
      await show(tester, wide);
      relay.calls.clear();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      expect(relay.calls, isNot(contains('sync')), reason: 'nothing reads while the tab is away');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(relay.calls, ['sync']);
      await finish(tester);
    });

    testWidgets("the phone's links to Account and Webhooks open Settings on that page, over the notes", (tester) async {
      space.answers.addAll({
        'GET account': (_) => {'email': 'you@example.com'},
        'GET connections': (_) => {'email': 'you@example.com'},
        'GET webhooks': (_) => {'webhooks': <Object>[], 'kinds': <Object>[]},
      });
      for (final (part, page) in [('account', SettingsPage.account), ('webhooks', SettingsPage.webhooks),
          ('devices', SettingsPage.account)]) {
        final at = SettingsPage.ofPart(Uri.parse('https://relay.example.com/apps/relay/#$part').fragment);
        expect([at, placeOfPart(part)], [page, isNull], reason: part);
        await show(tester, wide, settingsAt: at);
        expect(find.byType(SettingsView), findsOneWidget, reason: part);
        // Webhooks sits under Account in the list.
        expect(tester.widget<ListTile>(find.byKey(const ValueKey('settings-account'))).selected, isTrue, reason: part);
        expect(find.byType(NotesPane), findsOneWidget, reason: 'Settings opens over the notes');
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.byType(SettingsView), findsNothing);
        await finish(tester);
      }
      expect(SettingsPage.ofPart('/webhooks'), SettingsPage.webhooks, reason: "the app's own route in the address");
      expect(SettingsPage.ofPart(''), isNull);
      expect(SettingsPage.ofPart('/'), isNull);
    });

    test('an address part opens its place: the old AI apps and chats open Connect your AI', () {
      expect([placeOfPart('ai-apps'), placeOfPart('chats'), placeOfPart('/ai-apps')], everyElement(isA<ConnectAiPlace>()));
      expect(placeOfPart('email-notes'), isA<EmailNotesPlace>());
      expect([placeOfPart('saved-chats'), placeOfPart('/saved-chats')], everyElement(isA<ChatsPlace>()));
      expect([placeOfPart(''), placeOfPart('webhooks'), placeOfPart('chats/1'), placeOfPart('api-keys')], everyElement(isNull));
      expect([SettingsPage.ofPart('ai-apps'), SettingsPage.ofPart('email-notes'), SettingsPage.ofPart('saved-chats')],
        everyElement(isNull));
    });

    testWidgets('Connect your AI and Email notes open in the main pane; Saved chats opens the saved chats', (tester) async {
      space.answers.addAll({
        'GET connections': (_) => {'email': 'you@example.com', 'notesAddress': 'notes-k7q2m9xwab@in.example.com',
          'sharedAddress': 'notes@in.example.com'},
        'GET ai-apps': (_) => {'address': 'https://mcp.example.com', 'apps': <Object>[]},
        'GET chats': (_) => {'chats': <Object>[], 'next': null, 'nextId': null},
      });
      await show(tester, wide);
      await tester.tap(inSidebar('Connect your AI'));
      await tester.pumpAndSettle();
      expect(find.byType(WebConnectAiPage), findsOneWidget);
      expect(find.byType(NotesPane), findsNothing);
      await tester.tap(find.text('Saved chats'));
      await tester.pumpAndSettle();
      expect(find.byType(ChatsView), findsOneWidget);
      expect(space.count('GET chats'), 1);
      await tester.tap(inSidebar('Email notes'));
      await tester.pumpAndSettle();
      expect(find.byType(WebEmailNotesPage), findsOneWidget);
      expect(find.text('notes-k7q2m9xwab@in.example.com'), findsOneWidget);
      await finish(tester);
    });

    testWidgets("the phone's Read them on the web opens /#saved-chats on the saved chats", (tester) async {
      space.answers['GET chats'] = (_) => {'chats': <Object>[], 'next': null, 'nextId': null};
      final place = placeOfPart(Uri.parse('https://relay.example.com/#saved-chats').fragment);
      expect(place, isA<ChatsPlace>());
      await show(tester, wide, placeAt: place);
      expect(find.byType(ChatsView), findsOneWidget);
      expect(find.byType(NotesPane), findsNothing);
      expect(space.count('GET chats'), 1);
      await tester.tap(inSidebar('Notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPane), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('two panes from 700 px put the left bar in a menu', (tester) async {
    await show(tester, middle);
    expect(find.byType(NotesPane), findsOneWidget);
    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();
    expect(inSidebar('Other connections'), findsOneWidget);
    await tester.tap(inSidebar('Notes'));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing, reason: 'the menu closes');
    expect(inList('Groceries'), findsOneWidget);
    await finish(tester);
  });

  group('the phone pages below 700 px', () {
    testWidgets('Home shows one Notes row and Other connections in place of On this phone', (tester) async {
      await show(tester, narrow);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Other connections'), findsOneWidget);
      expect(find.text('On this phone'), findsNothing);
      expect([find.text('Connect your AI'), find.text('Email notes')], everyElement(findsOneWidget));
      expect([find.text('AI chat transcripts'), find.text('Voice notes'), find.text('Shares')], everyElement(findsNothing));
      await tester.tap(find.text('Notes').first);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Voice 1'));
      await tester.pumpAndSettle();
      expect(find.text('Groceries'), findsNothing);
      await tester.tap(find.text('Call the dentist at 3'));
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'voice');
      expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Notes')), findsOneWidget,
        reason: 'the note goes back to the list');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Voice 1')).selected, isTrue,
        reason: 'the list keeps its filter');
      await finish(tester);
    });

    testWidgets('New note writes, and a hold records nothing in the browser', (tester) async {
      await show(tester, narrow);
      expect(recordAction(tester), isEmpty);
      await tester.longPress(find.byType(NewNoteButton));
      await tester.pumpAndSettle();
      expect(relay.calls, isNot(contains('voice start')));
      expect(find.byType(NoteEditor), findsOneWidget, reason: 'a long press is a tap: it writes');
      await finish(tester);
    });

    testWidgets('/#saved-chats opens the saved chats as a page with Connect your AI to go back, then Home', (tester) async {
      space.answers.addAll({
        'GET chats': (_) => {'chats': <Object>[], 'next': null, 'nextId': null},
        'GET connections': (_) => {'email': 'you@example.com'},
        'GET ai-apps': (_) => {'address': 'https://mcp.example.com', 'apps': <Object>[]},
      });
      await show(tester, narrow, placeAt: const ChatsPlace());
      expect(find.byType(ChatsView), findsOneWidget);
      expect(find.byType(HomeScreen), findsNothing);
      await tester.tap(find.text('Connect your AI'));
      await tester.pumpAndSettle();
      expect(find.byType(WebConnectAiPage), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets('a connection opens as a page with Home to go back', (tester) async {
      await show(tester, narrow);
      await tester.tap(find.text('Location'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectionPage), findsOneWidget);
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets('a note opened after another holds only itself: once it closes, a phone edit to the first one shows',
      (tester) async {
    Map<String, Object?> phoneNote(String id, String text, int at) => {'id': id, 'clientId': null, 'mine': false,
      'source': 'typed', 'text': text, 'recordedAt': at, 'editedAt': null, 'device': 'iPhone', 'audio': false,
      'attachments': <Object>[]};
    final at = now.millisecondsSinceEpoch;
    space.answers['GET account'] = (_) => {'email': 'ana@example.com'};
    space.answers['GET notes'] = (_) => {'notes': [phoneNote('a', 'Alpha plan', at), phoneNote('b', 'Beta list', at - 1000)],
      'next': 9, 'more': false};
    late final WebRelay web;
    web = WebRelay(client: space.client, lastSend: (_, _, [_]) {});
    await web.start();
    tester.view
      ..physicalSize = wide
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
      home: WebShell(relay: web, client: space.client, drops: drops.stream, opener: (_) async => true)));
    await tester.pumpAndSettle();
    expect([editor(tester).id, web.openNote], ['a', 'a']);
    await tester.tap(inList('Beta list'));
    await tester.pumpAndSettle();
    expect([editor(tester).id, web.openNote], ['b', 'b']);
    await tester.tap(inSidebar('Health'));
    await tester.pumpAndSettle();
    expect(web.openNote, isNull, reason: 'the note before closed, so nothing gets the hold back');
    space.answers['GET notes'] = (_) => {'notes': [phoneNote('a', 'Alpha, changed on the phone', at)], 'next': 10,
      'more': false};
    unawaited(web.pullNotes());
    await tester.pumpAndSettle();
    expect(web.entries.firstWhere((entry) => entry.id == 'a').text, 'Alpha, changed on the phone');
    await finish(tester);
  });

  testWidgets("a browser voice note, which comes with no length, takes the player's length to show the time and seek",
      (tester) async {
    final at = now.millisecondsSinceEpoch;
    space.answers['GET account'] = (_) => {'email': 'ana@example.com'};
    space.answers['GET notes'] = (_) => {'notes': [{'id': 'v', 'clientId': null, 'mine': false, 'source': 'ring',
      'text': 'Call the dentist at 3', 'recordedAt': at, 'editedAt': null, 'device': 'Ring', 'audio': true, 'place': null,
      'attachments': <Object>[]}], 'next': 1, 'more': false};
    final player = FakePlayer()..length = const Duration(seconds: 8);
    addTearDown(player.dispose);
    final web = WebRelay(client: space.client, player: player, lastSend: (_, _, [_]) {});
    await web.start();
    expect(web.entries.single.recordings.single.length, isNull, reason: 'the server sends no length');
    tester.view
      ..physicalSize = wide
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
      home: WebShell(relay: web, client: space.client, drops: drops.stream, opener: (_) async => true)));
    await tester.pumpAndSettle();
    final page = pageOf(tester);
    final key = recordingKey(page);
    expect(page.viewOf(key)!['length'], isNull, reason: 'no time shows before the player knows the length');
    page.tap(key, 'play');
    await tester.pumpAndSettle();
    expect(page.viewOf(key)!['length'], 8000);
    page.tap(key, 'seek', 0.5);
    await tester.pumpAndSettle();
    expect(player.calls, contains('seek 4000'));
    expect(page.viewOf(key)!['position'], 4000, reason: 'the line fills as it plays');
    page.tap(key, 'pause');
    await tester.pumpAndSettle();
    expect([page.viewOf(key)!['position'], page.viewOf(key)!['playing']], [4000, false]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('a tap on the line of a browser voice note before its first play plays it, then goes to that place',
      (tester) async {
    final at = now.millisecondsSinceEpoch;
    space.answers['GET account'] = (_) => {'email': 'ana@example.com'};
    space.answers['GET notes'] = (_) => {'notes': [{'id': 'v', 'clientId': null, 'mine': false, 'source': 'ring',
      'text': 'Call the dentist at 3', 'recordedAt': at, 'editedAt': null, 'device': 'Ring', 'audio': true, 'place': null,
      'attachments': <Object>[]}], 'next': 1, 'more': false};
    final player = FakePlayer()..length = const Duration(seconds: 8);
    addTearDown(player.dispose);
    final web = WebRelay(client: space.client, player: player, lastSend: (_, _, [_]) {});
    await web.start();
    expect(web.entries.single.recordings.single.length, isNull, reason: 'the server sends no length');
    tester.view
      ..physicalSize = wide
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
      home: WebShell(relay: web, client: space.client, drops: drops.stream, opener: (_) async => true)));
    await tester.pumpAndSettle();
    final page = pageOf(tester);
    final key = recordingKey(page);
    page.tap(key, 'seek', 0.5);
    await tester.pumpAndSettle();
    expect(player.calls, ['play', 'seek 4000']);
    expect([page.viewOf(key)!['position'], page.viewOf(key)!['length']], [4000, 8000]);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('the open note gives its words to the page before the pause saves them, for a closing page', (tester) async {
    await show(tester, wide);
    await tapWords(tester);
    await write(tester, '# Groceries\nmilk and eggs and bread');
    expect(relay.calls.where((call) => call.startsWith('edit')), isEmpty, reason: 'the pause has not ended');
    final words = relay.editorWords!()!;
    expect(words.id, 'own');
    expect(words.text, contains('milk and eggs and bread'));
    await tester.tap(inSidebar('Health'));
    await tester.pumpAndSettle();
    expect(relay.editorWords, isNull, reason: 'no note is open');
    await finish(tester);
  });

  testWidgets('the open note and its unsaved words stay through each resize', (tester) async {
    await show(tester, wide);
    final first = editor(tester);
    final page = pageOf(tester);
    // The page's view keeps its place in the tree: a frame moved in the browser's page loads its page again.
    final view = tester.element(find.byType(FakePageView));
    await tapWords(tester);
    await write(tester, '# Groceries\nmilk and eggs and bread');
    for (final size in [middle, narrow, wide]) {
      await resize(tester, size);
      expect([editor(tester), pageOf(tester)], [same(first), same(page)], reason: '$size');
      expect(tester.element(find.byType(FakePageView)), same(view), reason: '$size');
      expect(markdownOf(tester), contains('milk and eggs and bread'), reason: '$size');
    }
    expect([page.sent('load').length, page.reloads], [1, 0]);
    await finish(tester);
  });

  testWidgets('in the narrow layout the page lets Ctrl+F through to the browser, and takes it again when wide',
      (tester) async {
    await show(tester, wide);
    final page = pageOf(tester);
    expect(page.loaded['appKeys'], ['new-note', 'find', 'delete-note']);
    await resize(tester, narrow);
    expect(page.sent('appKeys').last['appKeys'], ['new-note', 'delete-note'], reason: "the browser's own find runs");
    await resize(tester, wide);
    expect(page.sent('appKeys').last['appKeys'], ['new-note', 'find', 'delete-note']);
    expect(page.sent('load'), hasLength(1));
    await finish(tester);
  });

  testWidgets('a page that starts again by itself gets the note back, with its files and settings', (tester) async {
    await show(tester, wide);
    final page = pageOf(tester);
    await resize(tester, narrow);
    page
      ..posts.clear()
      ..boot();
    await tester.pumpAndSettle();
    final again = page.sent('load').single;
    expect([again['appKeys'], again['focus']], [['new-note', 'delete-note'], false]);
    expect(page.markdown, contains('milk and eggs'));
    await finish(tester);
  });

  group('keys', () {
    testWidgets('Ctrl+Alt+N starts a new note, and Cmd+Alt+N does too', (tester) async {
      await show(tester, wide);
      await press(tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft], LogicalKeyboardKey.keyN);
      expect(plainText(markdownOf(tester)).trim(), isEmpty);
      expect(editor(tester).id, isNot('own'));
      final first = editor(tester).id;
      await press(tester, [LogicalKeyboardKey.metaLeft, LogicalKeyboardKey.altLeft], LogicalKeyboardKey.keyN);
      expect(editor(tester).id, isNot(first));
      // The same key pressed in the note's words comes up from the page.
      final second = editor(tester).id;
      pageOf(tester).key('new-note');
      await tester.pumpAndSettle();
      expect(editor(tester).id, isNot(second));
      await finish(tester);
    });

    testWidgets('Ctrl+F goes to search, even from the open note', (tester) async {
      await show(tester, wide);
      await tapWords(tester);
      // The page passes Ctrl+F in the words up to the app.
      pageOf(tester).key('find');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField)));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.byType(Dialog), findsNothing, reason: "the editor's own find box stays shut");
      expect(pageOf(tester).runs.where((run) => run.startsWith('find')), isEmpty);
      await tester.tap(inSidebar('Health'));
      await tester.pumpAndSettle();
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyF);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField)))
        .focusNode!.hasFocus, isTrue);
      await finish(tester);
    });

    testWidgets('Ctrl+Shift+Backspace moves the open note to Recently Deleted with no message, and Ctrl+Z brings it back',
        (tester) async {
      await show(tester, wide);
      await press(tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.backspace);
      expect(relay.calls, contains('delete own'));
      expect([find.text('Undo'), find.byType(SnackBar)], everyElement(findsNothing));
      expect(sidebarCount('Recently Deleted', 1), findsOneWidget);
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyZ);
      expect([relay.calls.last, relay.deleted, inSidebar('Recently Deleted')], ['recover own', isEmpty, findsNothing]);
      // With no delete left to undo, the key does nothing here.
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyZ);
      expect(relay.calls.last, 'recover own');
      await finish(tester);
    });

    testWidgets("the page does Ctrl+B, Ctrl+I and the other format keys in the browser, and passes up the app's keys",
        (tester) async {
      await show(tester, wide);
      final load = pageOf(tester).loaded;
      expect([load['keys'], load['appKeys']], [true, ['new-note', 'find', 'delete-note']]);
      await finish(tester);
    });
  });

  group('format tools', () {
    testWidgets('Text styles opens a menu under it: a pick styles the line, closes the menu and gives the page the cursor',
        (tester) async {
      await show(tester, wide);
      await tapWords(tester);
      final page = pageOf(tester);
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pumpAndSettle();
      for (final item in ['Title', 'Heading', 'Subheading', 'Body', 'Monostyled', 'Bulleted List', 'Dashed List',
          'Numbered List', 'Block Quote']) {
        expect(find.widgetWithText(MenuItemButton, item), findsOneWidget, reason: item);
      }
      await tester.tap(find.widgetWithText(MenuItemButton, 'Heading'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(MenuItemButton, 'Heading'), findsNothing, reason: 'a pick closes the menu');
      expect(page.runs.skip(page.runs.length - 2), ['line heading', 'focus']);
      // The pen takes the colour picked in the menu, and the colour is kept.
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Pink'));
      await tester.pumpAndSettle();
      expect(relay.calls, contains('highlight pink'));
      expect(page.runs.last, 'recolour pink', reason: 'a highlight in the words picked takes the new colour');
      expect(page.sent('highlight').last['colour'], 'pink', reason: "the page's highlight key takes the new colour");
      await tester.tap(find.byTooltip('Highlight'));
      await tester.pumpAndSettle();
      expect(page.runs.skip(page.runs.length - 2), ['highlight pink', 'focus']);
      await finish(tester);
    });

    testWidgets("the open Text styles menu moves its ✓ to the line style the page says the cursor is on", (tester) async {
      await show(tester, wide);
      await tapWords(tester);
      final page = pageOf(tester)..say(kind: LineKind.header2);
      await tester.pump();
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pumpAndSettle();
      List<String> ticked() => [
        for (final style in ['Title', 'Heading', 'Subheading', 'Body', 'Monostyled'])
          if ((tester.widget<MenuItemButton>(find.widgetWithText(MenuItemButton, style)).leadingIcon! as SizedBox).child
            != null) style,
      ];
      expect(ticked(), ['Heading']);
      page.say(kind: LineKind.paragraph);
      await tester.pumpAndSettle();
      expect(ticked(), ['Body']);
      page.say(kind: LineKind.header2);
      await tester.pumpAndSettle();
      expect(ticked(), ['Heading']);
      await finish(tester);
    });
  });

  group('files dropped on the page', () {
    const card = NewFile(name: 'card.png', size: 3, bytes: [1, 2, 3]);

    testWidgets('join the open note', (tester) async {
      await show(tester, wide);
      drops.add([card]);
      await tester.pumpAndSettle();
      expect(relay.calls, contains('edit # Groceries\nmilk and eggs + card.png'));
      await finish(tester);
    });

    testWidgets('start a new note when none is open', (tester) async {
      await show(tester, narrow);
      drops.add([card]);
      await tester.pumpAndSettle();
      expect(relay.calls.where((call) => call.startsWith('note ')), ['note  + card.png']);
      expect(find.byType(NoteEditor), findsOneWidget);
      await finish(tester);
    });
  });

  group('phone-only parts', () {
    Future<void> settings(WidgetTester tester, RelayPlatform platform) async {
      relay.platform = platform;
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light), home: SettingsScreen(relay: relay)));
      await tester.pumpAndSettle();
    }

    testWidgets('Settings has no pin and no speech model in the browser', (tester) async {
      await settings(tester, RelayPlatform.web);
      expect(find.text('Pin notes to where I am'), findsNothing);
      expect(find.text('Speech model'), findsNothing);
      expect(find.text('Appearance'), findsOneWidget);
    });

    testWidgets('the phone keeps the speech model, and has no pin either', (tester) async {
      await settings(tester, RelayPlatform.phone);
      expect(find.text('Pin notes to where I am'), findsNothing);
      expect(find.text('Speech model'), findsOneWidget);
    });

    testWidgets("the phone's Home keeps On this phone, its own Other connections and the hold to talk", (tester) async {
      relay
        ..platform = RelayPlatform.phone
        ..entries = [];
      tester.view
        ..physicalSize = const Size(800, 1600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light), home: HomeScreen(relay: relay)));
      await tester.pumpAndSettle();
      expect(find.text('On this phone'), findsOneWidget);
      // On the phone, Other connections holds Connect your AI and Email notes, as in the browser.
      expect(find.text('Other connections'), findsOneWidget);
      expect([find.text('Connect your AI'), find.text('Email notes')], everyElement(findsOneWidget));
      expect(recordAction(tester), [CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Record a voice note'))]);
    });
  });

  group('pictures', () {
    Widget picture(EntryFile file) => MaterialApp(home: EntryImage(file: file, width: 40, height: 40,
      fallback: const Text('No picture')));

    testWidgets('the browser reads a picture from its address', (tester) async {
      await tester.pumpWidget(picture(const EntryFile(id: 'f1', name: 'card.png', type: 'image/png', size: 3,
        url: 'https://relay.example.com/apps/relay/api/attachment?id=f1')));
      final image = tester.widget<Image>(find.byType(Image));
      expect((image.image as NetworkImage).url, 'https://relay.example.com/apps/relay/api/attachment?id=f1');
      expect(const EntryFile(name: 'card.png', type: 'image/png', size: 3, url: 'x').ready, isTrue);
    });

    testWidgets('the phone reads its own copy', (tester) async {
      await tester.pumpWidget(picture(const EntryFile(name: 'card.png', type: 'image/png', size: 3, path: '/files/card.png')));
      expect(tester.widget<Image>(find.byType(Image)).image, isA<FileImage>());
    });

    testWidgets('a file still on its way shows its stand-in', (tester) async {
      await tester.pumpWidget(picture(const EntryFile(id: 'f2', name: 'card.png', type: 'image/png', size: 3)));
      expect(find.text('No picture'), findsOneWidget);
      expect(const EntryFile(name: 'card.png', type: 'image/png', size: 3).ready, isFalse);
    });
  });
}
