import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, ChangeSource, QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/screens/connected_names.dart' show ConnectedKind;
import 'package:relay_app/screens/home.dart';
import 'package:relay_app/screens/note_bars.dart';
import 'package:relay_app/screens/note_blocks.dart';
import 'package:relay_app/screens/note_editor.dart';
import 'package:relay_app/screens/settings.dart';
import 'package:relay_app/screens/timeline.dart' show TimelineScreen;
import 'package:relay_app/web/connection_page.dart';
import 'package:relay_app/web/settings_dialog.dart';
import 'package:relay_app/web/shell.dart';
import 'package:relay_app/web/web_relay.dart';

import 'screens_test.dart' show FakeRelay, quill, type;
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
        Entry(id: 'voice', text: 'Call the dentist at 3', at: now.subtract(const Duration(hours: 1)), sent: true, voice: true,
          from: 'iPhone'),
        Entry(id: 'link', text: 'Read https://example.com/post', at: now.subtract(const Duration(days: 1)), sent: true,
          from: 'Email'),
      ];
    space = FakeSpace();
    drops = StreamController<List<NewFile>>.broadcast();
  });

  tearDown(() => drops.close());

  Future<void> show(WidgetTester tester, Size size, {SettingsPage? settingsAt}) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: brandTheme(Brightness.light),
      home: WebShell(relay: relay, client: space.client, drops: drops.stream, opener: (_) async => true,
        settingsAt: settingsAt)));
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

  group('three panes from 1000 px', () {
    testWidgets('the left bar has the folders with counts, Other connections, and Settings at the bottom', (tester) async {
      await show(tester, wide);
      expect(inSidebar('Relay Everything'), findsOneWidget);
      expect(sidebarCount('Notes', 3), findsOneWidget);
      expect(sidebarCount('Voice notes', 1), findsOneWidget);
      expect(sidebarCount('Shares', 1), findsOneWidget);
      for (final title in ['Other connections', 'Location', 'Health', 'Calendar', 'Photos', 'Claude Code chats']) {
        expect(inSidebar(title), findsOneWidget, reason: title);
      }
      expect(tester.getTopLeft(inSidebar('Settings')).dy, greaterThan(tester.getTopLeft(inSidebar('Claude Code chats')).dy + 100),
        reason: 'Settings sits at the bottom of the left bar');
      await finish(tester);
    });

    testWidgets('the newest note opens in the right pane, with every tool in the top bar and nothing at the bottom',
        (tester) async {
      await show(tester, wide);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(editor(tester).id, 'own');
      expect(quill(tester).document.toPlainText(), startsWith('Groceries'));
      for (final tool in ['New note', 'Text styles', 'Checklist', 'Attach', 'Share', 'More']) {
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

    testWidgets('a click on a note opens it, and a folder shows only its notes', (tester) async {
      await show(tester, wide);
      await tester.tap(inList('Call the dentist at 3'));
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'voice');
      await tester.tap(inSidebar('Shares'));
      await tester.pumpAndSettle();
      expect(inList('Read https://example.com/post'), findsOneWidget);
      expect(inList('Groceries'), findsNothing);
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
      await tester.tap(inSidebar('Voice notes'));
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

    testWidgets("the phone's links to Webhooks and AI apps open Settings on that page, over the notes", (tester) async {
      space.answers['GET inbox'] = (_) => {'email': {'on': false}};
      space.answers['GET webhooks'] = (_) => {'webhooks': <Object>[], 'kinds': <Object>[]};
      space.answers['GET ai-apps'] = (_) => {'address': 'https://relay-mcp.example.com/mcp', 'apps': <Object>[]};
      for (final kind in ConnectedKind.values) {
        final page = SettingsPage.ofPart(Uri.parse('https://relay.example.com/apps/relay/${kind.part}').fragment);
        expect(page, isNotNull, reason: kind.part);
        await show(tester, wide, settingsAt: page);
        expect(find.byType(SettingsView), findsOneWidget, reason: kind.part);
        expect(tester.widget<ListTile>(find.byKey(ValueKey('settings-${page!.name}'))).selected, isTrue, reason: kind.part);
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
  });

  testWidgets('two panes from 700 px put the left bar in a menu', (tester) async {
    await show(tester, middle);
    expect(find.byType(NotesPane), findsOneWidget);
    expect(find.byType(NoteEditor), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();
    expect(inSidebar('Other connections'), findsOneWidget);
    await tester.tap(inSidebar('Voice notes'));
    await tester.pumpAndSettle();
    expect(find.byType(Sidebar), findsNothing, reason: 'the menu closes');
    expect(inList('Groceries'), findsNothing);
    await finish(tester);
  });

  group('the phone pages below 700 px', () {
    testWidgets('Home shows the folders and Other connections in place of On this phone', (tester) async {
      await show(tester, narrow);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Other connections'), findsOneWidget);
      expect(find.text('On this phone'), findsNothing);
      expect(find.text('Claude Code chats'), findsOneWidget);
      await tester.tap(find.text('Voice notes').first);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
      await tester.tap(find.text('Call the dentist at 3'));
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'voice');
      expect(find.text('Voice notes'), findsOneWidget, reason: 'the note goes back to its folder');
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
      'source': 'typed', 'text': text, 'recordedAt': at, 'editedAt': null, 'device': 'iPhone', 'audio': false, 'place': null,
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

  testWidgets('the open note gives its words to the page before the pause saves them, for a closing page', (tester) async {
    await show(tester, wide);
    await tester.tap(find.byType(QuillEditor));
    await tester.pump();
    quill(tester).updateSelection(TextSelection.collapsed(offset: quill(tester).document.length - 1), ChangeSource.local);
    await type(tester, ' and bread');
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
    quill(tester).updateSelection(TextSelection.collapsed(offset: quill(tester).document.length - 1), ChangeSource.local);
    await type(tester, ' and bread');
    for (final size in [middle, narrow, wide]) {
      await resize(tester, size);
      expect(editor(tester), same(first), reason: '$size');
      expect(quill(tester).document.toPlainText(), contains('milk and eggs and bread'), reason: '$size');
    }
    await finish(tester);
  });

  group('keys', () {
    testWidgets('Ctrl+Alt+N starts a new note, and Cmd+Alt+N does too', (tester) async {
      await show(tester, wide);
      await press(tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.altLeft], LogicalKeyboardKey.keyN);
      expect(quill(tester).document.toPlainText(), '\n');
      expect(editor(tester).id, isNot('own'));
      await finish(tester);
    });

    testWidgets('Ctrl+F goes to search, even from the open note', (tester) async {
      await show(tester, wide);
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyF);
      final field = tester.widget<TextField>(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField)));
      expect(field.focusNode!.hasFocus, isTrue);
      expect(find.byType(Dialog), findsNothing, reason: "the editor's own find box stays shut");
      await tester.tap(inSidebar('Health'));
      await tester.pumpAndSettle();
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyF);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(tester.widget<TextField>(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField)))
        .focusNode!.hasFocus, isTrue);
      await finish(tester);
    });

    testWidgets('Ctrl+Shift+Backspace deletes the open note with Undo', (tester) async {
      await show(tester, wide);
      await press(tester, [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft], LogicalKeyboardKey.backspace);
      expect(relay.calls, contains('delete own'));
      expect(find.text('Undo'), findsOneWidget);
      await finish(tester);
    });

    testWidgets("Ctrl+B and Ctrl+I are the editor's bold and italic", (tester) async {
      await show(tester, wide);
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection(baseOffset: 10, extentOffset: 14), ChangeSource.local);
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyB);
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyI);
      final style = quill(tester).getSelectionStyle().attributes;
      expect(style.containsKey(Attribute.bold.key), isTrue);
      expect(style.containsKey(Attribute.italic.key), isTrue);
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

    testWidgets('the phone keeps them', (tester) async {
      await settings(tester, RelayPlatform.phone);
      expect(find.text('Pin notes to where I am'), findsOneWidget);
      expect(find.text('Speech model'), findsOneWidget);
    });

    testWidgets("the phone's Home keeps On this phone and the hold to talk", (tester) async {
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
      expect(find.text('Other connections'), findsNothing);
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
