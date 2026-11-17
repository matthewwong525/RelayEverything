import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show Attribute, ChangeSource, QuillEditor;
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:relay_app/data/files.dart' show checkFiles;
import 'package:relay_app/mac/drops.dart';
import 'package:relay_app/mac/mac_app.dart';
import 'package:relay_app/mac/updates.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/connect.dart' show ConnectScreen;
import 'package:relay_app/screens/connect_ai.dart' show ConnectAiPage;
import 'package:relay_app/screens/email_notes.dart' show EmailNotesPage;
import 'package:relay_app/screens/hold_to_talk.dart' show NewNoteButton;
import 'package:relay_app/screens/home.dart';
import 'package:relay_app/screens/note_blocks.dart' show RecordingCard, RecordingPage;
import 'package:relay_app/screens/note_editor.dart';
import 'package:relay_app/screens/settings.dart';
import 'package:relay_app/screens/timeline.dart' show TimelineScreen;
import 'package:relay_app/screens/transcripts.dart' show TranscriptsPage;
import 'package:relay_app/web/shell.dart';

import 'screens_test.dart' show FakeRelay, markdownOf, quill;

const wide = Size(1200, 900);
const middle = Size(800, 800);
const narrow = Size(500, 844);

/// A Mac whose note keeps a file only up to 25 MB, as the controller does.
class _MacRelay extends FakeRelay {
  @override
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true}) async {
    await super.editNote(id, text, files: files, sendNow: sendNow);
    return checkFiles(const [], files).problem;
  }
}

void main() {
  late _MacRelay relay;
  late StreamController<List<NewFile>> drops;
  late List<Uri> opened;
  final now = DateTime.now();

  setUp(() {
    PackageInfo.setMockInitialValues(appName: 'Relay Everything', packageName: 'com.matthewwong525.relayApp.mac',
      version: '1.4.0', buildNumber: '1', buildSignature: '');
    relay = _MacRelay()
      ..platform = RelayPlatform.mac
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..entries = [
        Entry(id: 'own', text: '# Groceries\nmilk and eggs', at: now, sent: true),
        Entry(id: 'voice', text: '', at: now.subtract(const Duration(hours: 1)), sent: true, from: 'iPhone', recordings: const [
          EntryRecording(id: 'r1', recording: 'r1', transcript: 'Call the dentist at 3', length: Duration(seconds: 8), top: true)]),
      ];
    drops = StreamController<List<NewFile>>.broadcast();
    opened = [];
  });

  tearDown(() => drops.close());

  Future<void> show(WidgetTester tester, Size size) async {
    // The menu bar goes to the Mac's own menus, which a test has none of.
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, (_) async => null);
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.menu, null));
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MacApp(relay: relay, drops: drops.stream, opener: (address) async {
      opened.add(address);
      return true;
    }));
    await tester.pumpAndSettle();
  }

  /// Takes the window away and lets each wait end, so no timer stays after the test.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  }

  Finder inSidebar(String text) => find.descendant(of: find.byType(Sidebar), matching: find.text(text));

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

  /// The menu bar's item named [label], in any menu.
  PlatformMenuItem menuItem(WidgetTester tester, String label) {
    Iterable<PlatformMenuItem> walk(List<PlatformMenuItem> items) sync* {
      for (final item in items) {
        yield item;
        if (item is PlatformMenu) yield* walk(item.menus);
        if (item is PlatformMenuItemGroup) yield* walk(item.members);
      }
    }
    return walk(tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus).singleWhere((item) => item.label == label);
  }

  Future<void> select(WidgetTester tester, String label) async {
    menuItem(tester, label).onSelected!();
    await tester.pumpAndSettle();
  }

  NoteEditorState editor(WidgetTester tester) => tester.state<NoteEditorState>(find.byType(NoteEditor));

  bool searchHasFocus(WidgetTester tester) =>
    tester.widget<TextField>(find.descendant(of: find.byType(SearchField), matching: find.byType(TextField))).focusNode!.hasFocus;

  group('three parts from 1,000 px', () {
    testWidgets('the left bar has Notes, Connect your AI, Email notes and Settings, and no phone connection',
        (tester) async {
      await show(tester, wide);
      expect(find.byType(Sidebar), findsOneWidget);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(editor(tester).id, 'own');
      for (final title in ['Notes', 'Other connections', 'Connect your AI', 'Email notes', 'Settings']) {
        expect(inSidebar(title), findsOneWidget, reason: title);
      }
      for (final title in ['Location', 'Health', 'Calendar', 'Photos']) {
        expect(inSidebar(title), findsNothing, reason: title);
      }
      await finish(tester);
    });

    testWidgets("Settings, Connect your AI and Email notes show the phone's pages in the right part", (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.byType(NotesPane), findsNothing);
      expect(find.byType(Dialog), findsNothing, reason: 'the Mac has no Settings window over the notes');
      expect(find.byTooltip('Back'), findsNothing, reason: 'the left bar goes back');
      await tester.tap(inSidebar('Connect your AI'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectAiPage), findsOneWidget);
      await tester.tap(inSidebar('Email notes'));
      await tester.pumpAndSettle();
      expect(find.byType(EmailNotesPage), findsOneWidget);
      await tester.tap(inSidebar('Notes'));
      await tester.pumpAndSettle();
      expect(find.byType(NotesPane), findsOneWidget);
      await finish(tester);
    });

    testWidgets('Saved chats opens in the same part, and Read them on the web opens /#saved-chats', (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Connect your AI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saved chats'));
      await tester.pumpAndSettle();
      expect(find.byType(TranscriptsPage), findsOneWidget);
      expect(find.byType(Sidebar), findsOneWidget);
      await tester.tap(find.text('Read them on the web'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://relay.example.com/#saved-chats')]);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectAiPage), findsOneWidget);
      await finish(tester);
    });
  });

  testWidgets("a phone's recording shows as its card, plays, and opens its transcript's page, and the Mac shows no Record",
      (tester) async {
    await show(tester, wide);
    await tester.tap(find.descendant(of: find.byType(NotesPane), matching: find.text('Call the dentist at 3')));
    await tester.pumpAndSettle();
    expect(editor(tester).id, 'voice');
    final card = find.byType(RecordingCard);
    expect([find.descendant(of: card, matching: find.text('Transcript')),
      find.descendant(of: card, matching: find.byTooltip('Play'))], everyElement(findsOneWidget));
    expect(find.byTooltip('Record'), findsNothing);
    await tester.tap(find.descendant(of: card, matching: find.byTooltip('Play')));
    await tester.pump();
    expect(relay.calls, contains('play r1'));
    // The recording's page opens on the Mac too, with the words to read.
    await tester.tap(find.descendant(of: card, matching: find.text('Transcript')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(RecordingPage), matching: find.widgetWithText(SelectableText, 'Call the dentist at 3')),
      findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('two parts from 700 px put the left bar in a menu, with the same rows', (tester) async {
    await show(tester, middle);
    expect(find.byType(NotesPane), findsOneWidget);
    expect(find.byType(Sidebar), findsNothing);
    await tester.tap(find.byTooltip('Folders'));
    await tester.pumpAndSettle();
    expect(inSidebar('Connect your AI'), findsOneWidget);
    expect(inSidebar('Health'), findsNothing);
    await tester.tap(inSidebar('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('coming back to the window sends and reads the notes changed elsewhere', (tester) async {
    await show(tester, wide);
    relay.calls.clear();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    expect(relay.calls, isNot(contains('pull')), reason: 'nothing reads while the window is away');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(relay.calls, ['pull'], reason: "the controller's pull sends what waits, then reads");
    await finish(tester);
  });

  group('one part below 700 px', () {
    testWidgets('Home has no phone connection and no hold to talk', (tester) async {
      await show(tester, narrow);
      expect(find.byType(HomeScreen), findsOneWidget);
      expect([find.text('Connect your AI'), find.text('Email notes')], everyElement(findsOneWidget));
      expect([find.text('Location'), find.text('Health'), find.text('Calendar'), find.text('Photos')],
        everyElement(findsNothing));
      await tester.longPress(find.byType(NewNoteButton));
      await tester.pumpAndSettle();
      expect(relay.calls, isNot(contains('voice start')));
      expect(find.byType(NoteEditor), findsOneWidget, reason: 'a long press is a tap: it writes');
      await finish(tester);
    });

    testWidgets('signed out, the empty notes and Settings say the notes stay on this Mac', (tester) async {
      relay
        ..connected = false
        ..settings = const Settings()
        ..entries = [];
      await show(tester, narrow);
      await tester.tap(find.text('Notes').first);
      await tester.pumpAndSettle();
      expect(find.text('Notes stay on this Mac until you sign in, in Settings.'), findsOneWidget);
      expect(find.textContaining('this phone'), findsNothing);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Your notes stay on this Mac until you sign in.'), findsOneWidget);
      expect(find.textContaining('this phone'), findsNothing);
      await finish(tester);
    });

    testWidgets("Settings is the phone's page, and its back goes Home", (tester) async {
      await show(tester, narrow);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.tap(find.text('Notes').first);
      await tester.pumpAndSettle();
      expect(find.byType(TimelineScreen), findsOneWidget);
      await finish(tester);
    });
  });

  group('menus and keys', () {
    testWidgets('the menu bar has New Note, Find, Bold, Italic and Settings… with their keys', (tester) async {
      await show(tester, wide);
      final keys = {
        'New Note': LogicalKeyboardKey.keyN,
        'Find': LogicalKeyboardKey.keyF,
        'Bold': LogicalKeyboardKey.keyB,
        'Italic': LogicalKeyboardKey.keyI,
        'Settings…': LogicalKeyboardKey.comma,
      };
      for (final MapEntry(key: label, value: key) in keys.entries) {
        final shortcut = menuItem(tester, label).shortcut! as SingleActivator;
        expect([shortcut.trigger, shortcut.meta, shortcut.shift, shortcut.control], [key, true, false, false], reason: label);
      }
      for (final label in ['Undo', 'Cut', 'Copy', 'Paste', 'Select All']) {
        expect(menuItem(tester, label).onSelected, isNotNull, reason: label);
      }
      await finish(tester);
    });

    testWidgets("Undo from the Edit menu and ⌘Z bring back the last deleted note while no words are typed", (tester) async {
      await show(tester, wide);
      await relay.deleteNote('voice');
      await relay.deleteNote('own');
      await tester.pumpAndSettle();
      expect(inSidebar('Recently Deleted'), findsOneWidget);
      await select(tester, 'Undo');
      expect(relay.calls.last, 'recover own');
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyZ);
      expect([relay.calls.last, relay.deleted, inSidebar('Recently Deleted')], ['recover voice', isEmpty, findsNothing]);
      await finish(tester);
    });

    testWidgets('New Note from the menu and ⌘N both start a new note, from any place', (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Settings'));
      await tester.pumpAndSettle();
      await select(tester, 'New Note');
      expect(find.byType(NotesPane), findsOneWidget);
      expect(quill(tester).document.toPlainText(), '\n');
      expect(editor(tester).id, isNot('own'));
      await tester.tap(find.text('Groceries').first);
      await tester.pumpAndSettle();
      expect(editor(tester).id, 'own');
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyN);
      expect(quill(tester).document.toPlainText(), '\n');
      expect(editor(tester).id, isNot('own'));
      await finish(tester);
    });

    testWidgets('Find from the menu and ⌘F both go to search', (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Email notes'));
      await tester.pumpAndSettle();
      await select(tester, 'Find');
      expect(find.byType(NotesPane), findsOneWidget);
      expect(searchHasFocus(tester), isTrue);
      await tester.tap(inSidebar('Email notes'));
      await tester.pumpAndSettle();
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.keyF);
      expect(find.byType(NotesPane), findsOneWidget);
      expect(searchHasFocus(tester), isTrue);
      await finish(tester);
    });

    testWidgets('Settings… from the menu and ⌘, both open Settings', (tester) async {
      await show(tester, wide);
      await select(tester, 'Settings…');
      expect(find.byType(SettingsScreen), findsOneWidget);
      await tester.tap(inSidebar('Notes'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing);
      await press(tester, [LogicalKeyboardKey.metaLeft], LogicalKeyboardKey.comma);
      expect(find.byType(SettingsScreen), findsOneWidget);
      await finish(tester);
    });

    testWidgets("Bold and Italic from the menu style the words picked, as the editor's keys do", (tester) async {
      await show(tester, wide);
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection(baseOffset: 10, extentOffset: 14), ChangeSource.local);
      await select(tester, 'Bold');
      await select(tester, 'Italic');
      var style = quill(tester).getSelectionStyle().attributes;
      expect(style.containsKey(Attribute.bold.key), isTrue);
      expect(style.containsKey(Attribute.italic.key), isTrue);
      // The editor's own key takes it off again: the menu and the key change the same style.
      await press(tester, [LogicalKeyboardKey.controlLeft], LogicalKeyboardKey.keyB);
      style = quill(tester).getSelectionStyle().attributes;
      expect(style.containsKey(Attribute.bold.key), isFalse);
      await select(tester, 'Italic');
      style = quill(tester).getSelectionStyle().attributes;
      expect(style.containsKey(Attribute.italic.key), isFalse);
      await finish(tester);
    });

    testWidgets('the Format menu has each format item with its keys, and Title styles the line', (tester) async {
      await show(tester, wide);
      final format = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus.whereType<PlatformMenu>()
        .singleWhere((menu) => menu.label == 'Format');
      expect([
        for (final group in format.menus.cast<PlatformMenuItemGroup>())
          for (final item in group.members) item.label,
      ], ['Bold', 'Italic', 'Underline', 'Strikethrough', 'Highlight', 'Title', 'Heading', 'Subheading', 'Body',
        'Monostyled', 'Bulleted List', 'Dashed List', 'Numbered List', 'Checklist', 'Mark as Ticked', 'Block Quote',
        'Indent More', 'Indent Less', 'Link…', 'Table']);
      final keys = {
        'Bold': (LogicalKeyboardKey.keyB, false, false),
        'Underline': (LogicalKeyboardKey.keyU, false, false),
        'Strikethrough': (LogicalKeyboardKey.keyX, true, false),
        'Highlight': (LogicalKeyboardKey.keyE, true, false),
        'Title': (LogicalKeyboardKey.keyT, true, false),
        'Heading': (LogicalKeyboardKey.keyH, true, false),
        'Subheading': (LogicalKeyboardKey.keyJ, true, false),
        'Body': (LogicalKeyboardKey.keyB, true, false),
        'Monostyled': (LogicalKeyboardKey.keyM, true, false),
        'Bulleted List': (LogicalKeyboardKey.digit7, true, false),
        'Dashed List': (LogicalKeyboardKey.digit8, true, false),
        'Numbered List': (LogicalKeyboardKey.digit9, true, false),
        'Checklist': (LogicalKeyboardKey.keyL, true, false),
        'Mark as Ticked': (LogicalKeyboardKey.keyU, true, false),
        'Block Quote': (LogicalKeyboardKey.quoteSingle, false, false),
        'Indent More': (LogicalKeyboardKey.bracketRight, false, false),
        'Indent Less': (LogicalKeyboardKey.bracketLeft, false, false),
        'Link…': (LogicalKeyboardKey.keyK, false, false),
        'Table': (LogicalKeyboardKey.keyT, false, true),
      };
      for (final MapEntry(key: label, value: (key, shift, alt)) in keys.entries) {
        final shortcut = menuItem(tester, label).shortcut! as SingleActivator;
        expect([shortcut.trigger, shortcut.meta, shortcut.control, shortcut.shift, shortcut.alt], [key, true, false, shift, alt],
          reason: label);
      }
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 14), ChangeSource.local);
      await select(tester, 'Title');
      expect(markdownOf(tester), '# Groceries\n# milk and eggs');
      await select(tester, 'Body');
      expect(markdownOf(tester), '# Groceries\nmilk and eggs');
      await finish(tester);
    });
  });

  group('updates', () {
    testWidgets('Check for Updates… sits in the app menu after About, before Settings…, with no key, and checks',
        (tester) async {
      await show(tester, wide);
      final appMenu = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar)).menus.first as PlatformMenu;
      final groups = [for (final group in appMenu.menus.whereType<PlatformMenuItemGroup>())
        [for (final item in group.members) item.label]];
      expect(groups.indexWhere((labels) => labels.contains('Check for Updates…')),
        lessThan(groups.indexWhere((labels) => labels.contains('Settings…'))));
      expect(menuItem(tester, 'Check for Updates…').shortcut, isNull);
      await select(tester, 'Check for Updates…');
      expect(relay.calls, ['check for updates']);
      await finish(tester);
    });

    testWidgets('Settings has Updates between Appearance and the version: Check for Updates… checks, and Get test '
        'builds turns on and stays on', (tester) async {
      await show(tester, wide);
      await tester.tap(inSidebar('Settings'));
      await tester.pumpAndSettle();
      final top = [for (final text in ['Appearance', 'Updates', 'Relay Everything 1.4.0 (1)']) tester.getTopLeft(find.text(text)).dy];
      expect(top, orderedEquals([...top]..sort()));
      await tester.tap(find.text('Check for Updates…'));
      await tester.pumpAndSettle();
      SwitchListTile testBuilds() => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Get test builds'));
      expect(testBuilds().value, isFalse, reason: 'off by default: only full releases');
      await tester.tap(find.text('Get test builds'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['check for updates', 'test builds true']);
      expect(testBuilds().value, isTrue);
      await finish(tester);
    });

    test("MacUpdates calls Sparkle's channel by name", () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = MethodChannel('relay/updates');
      final calls = <String>[];
      final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        ..setMockMethodCallHandler(channel, (call) async => calls.add('${call.method} ${call.arguments}'));
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      const updates = MacUpdates();
      await updates.check();
      await updates.checkInBackground();
      await updates.setTestBuilds(true);
      expect(calls, ['check null', 'checkInBackground null', 'setTestBuilds true']);
    });
  });

  testWidgets('the sign-in says Mac, not phone', (tester) async {
    relay.connected = false;
    await tester.pumpWidget(MaterialApp(home: ConnectScreen(relay: relay)));
    expect(find.text('Your notes stay on this Mac until you sign in.'), findsOneWidget);
    expect(find.textContaining('phone'), findsNothing);
  });

  group('files dropped from Finder', () {
    testWidgets('join the open note', (tester) async {
      await show(tester, wide);
      drops.add(const [NewFile(path: '/Users/sam/Desktop/card.png', name: 'card.png', size: 3)]);
      await tester.pumpAndSettle();
      expect(relay.calls, contains('edit # Groceries\nmilk and eggs + card.png'));
      expect(find.textContaining('over 25 MB'), findsNothing);
      await finish(tester);
    });

    testWidgets('a file over 25 MB is not added, with the words that say so', (tester) async {
      await show(tester, wide);
      drops.add(const [NewFile(path: '/Users/sam/Movies/trip.mov', name: 'trip.mov', size: 26 * 1024 * 1024)]);
      await tester.pumpAndSettle();
      // An alert: the one sentence is its title.
      expect(find.text('trip.mov is over 25 MB, so it was not added'), findsOneWidget);
      await finish(tester);
    });

    test("a drop's files keep their path, name and size, and a folder is left out", () async {
      final file = DropItemFile.fromData(Uint8List.fromList([1, 2, 3, 4]), name: 'card.png', path: '/tmp/card.png');
      final folder = DropItemDirectory('/tmp/trips', const [], name: 'trips');
      final accessed = <String>[];
      final files = await droppedFiles([file, folder], access: (item) async => accessed.add(item.name));
      expect([for (final file in files) (file.path, file.name, file.size)], [('/tmp/card.png', 'card.png', 4)]);
      expect(accessed, ['card.png']);
    });
  });
}
