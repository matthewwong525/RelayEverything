import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/editor/markdown.dart' show LineKind, kindOf;
import 'package:relay_app/editor/note_commands.dart';
import 'package:relay_app/editor/system_menu.dart';
import 'package:relay_app/editor/table.dart' show NoteTableView, cellPause;
import 'package:relay_app/relay.dart' show Entry, EntryFile;
import 'package:relay_app/screens/note_editor.dart';

import 'package:super_editor/super_editor.dart' show ImeInputOwner, SuperEditorImeInteractor,
  SuperEditorIosControlsController, SuperEditorIosControlsScope, boldAttribution;

import 'screens_test.dart' show FakeRelay, caretOf, editorFocused, note, now, openFolder;

const words = 'Buy milk and eggs\nhttps://example.com/list\nCall Sam';

/// The system menu messages the app sends to the phone, kept in order.
List<MethodCall> menuCalls(WidgetTester tester) {
  final calls = <MethodCall>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method.startsWith('ContextMenu.')) calls.add(call);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
  return calls;
}

List<String> methods(List<MethodCall> calls) => [for (final call in calls) call.method.replaceFirst('ContextMenu.', '')];

/// The items a show message asks for: the kind of each of the phone's own, such as `paste`, and the title of each the
/// app runs, such as `Copy`.
List<String> itemsOf(MethodCall call) => [
  for (final item in (call.arguments as Map)['items'] as List)
    if ((item as Map)['type'] == 'custom') item['title'] as String else item['type'] as String,
];

/// The phone tells the app it ran the item titled [title] of the last menu, then that it closed the menu, in the
/// order the phone sends them.
Future<void> pressItem(WidgetTester tester, List<MethodCall> calls, String title) async {
  final items = (calls.lastWhere((call) => call.method == 'ContextMenu.showSystemContextMenu').arguments as Map)['items'];
  final id = (items as List).cast<Map>().firstWhere((item) => item['title'] == title)['id'];
  for (final call in [MethodCall('ContextMenu.onPerformCustomAction', [0, id]),
      const MethodCall('ContextMenu.onDismissSystemContextMenu')]) {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(SystemChannels.platform.name,
      SystemChannels.platform.codec.encodeMethodCall(call), (_) {});
  }
  await tester.pumpAndSettle();
}

/// The note's iPhone controls: its menu and its magnifier.
SuperEditorIosControlsController iosControls(WidgetTester tester) =>
  tester.widget<SuperEditorIosControlsScope>(find.byType(SuperEditorIosControlsScope).first).controller;

/// Whether the note's iPhone menu is up.
bool toolbarShown(WidgetTester tester) => iosControls(tester).shouldShowToolbar.value;

/// The screen point of the blinking cursor.
Offset cursorAt(WidgetTester tester) => caretOf(tester).center;

/// The point [dx] points into the line [line], half way down it.
Offset onLine(WidgetTester tester, String line, double dx) =>
  tester.getTopLeft(find.text(line, findRichText: true)) + Offset(dx, tester.getSize(find.text(line, findRichText: true)).height / 2);

/// The iPhone's own *Paste* hands the app the clipboard's [html] and [plain] words, as RelayPaste.swift sends them;
/// the app's answer, or null with none.
Future<Object?> phonePaste(WidgetTester tester, {String? html, required String plain}) async {
  Object? answer;
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(pasteChannel.name,
    pasteChannel.codec.encodeMethodCall(MethodCall('paste', {'html': html, 'plain': plain})),
    (data) => answer = data == null ? null : pasteChannel.codec.decodeEnvelope(data));
  await tester.pump();
  return answer;
}

/// The phone's clipboard: plain words for `Clipboard.getData`, and the words `Clipboard.setData` puts there.
void plainClipboard(WidgetTester tester, String Function() words, {void Function(String)? onCopy}) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.getData') return {'text': words()};
    if (call.method == 'Clipboard.setData') onCopy?.call((call.arguments as Map)['text'] as String);
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
}

/// A clipboard that holds [html], as a page's copy does: the Mac app's `relay/clipboard` answers with it.
void htmlClipboard(WidgetTester tester, String html) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(clipboardChannel, (call) async => html);
  addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(clipboardChannel, null));
}

/// Presses [key] with Ctrl held, as a keyboard does.
Future<void> controlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

/// The note's words as it stores them.
String stored(WidgetTester tester) => note(tester).markdown;

/// Whether the phone can show its own menu: iOS 16 and later. The view's media data keeps its value until told.
void systemMenuOn(WidgetTester tester, bool supported) {
  tester.platformDispatcher.supportsShowingSystemContextMenu = supported;
  tester.binding.handleMetricsChanged();
  addTearDown(() {
    tester.platformDispatcher.resetSupportsShowingSystemContextMenu();
    tester.binding.handleMetricsChanged();
  });
}

void main() {
  late FakeRelay relay;
  setUp(() => relay = FakeRelay()..entries = [Entry(id: 'n1', text: words, at: now)]);

  /// Opens the note and taps at the end of its first line, so the keyboard is up and the cursor sits there.
  Future<void> editNote(WidgetTester tester, {bool systemMenu = true, String open = 'Buy milk and eggs'}) async {
    systemMenuOn(tester, systemMenu);
    await tester.pumpWidget(RelayApp(relay: relay, opener: (_) async => true));
    await openFolder(tester, 'Notes');
    await tester.tap(find.text(open).first);
    await tester.pumpAndSettle();
    await tester.tapAt(onLine(tester, 'Buy milk and eggs', 10));
    await tester.pump(const Duration(seconds: 1));
    note(tester).select(const TextSelection.collapsed(offset: 17));
    await tester.pump();
    expect(editorFocused(tester), isTrue);
  }

  group('on an iPhone with the system menu', () {
    testWidgets('a hold in the words shows the iPhone\'s own menu with Paste, and Flutter draws no menu', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      await tester.longPressAt(onLine(tester, 'Buy milk and eggs', 30));
      await tester.pumpAndSettle();
      expect(methods(calls), ['showSystemContextMenu']);
      // A hold picks the word under the finger, as in Notes: the menu acts on it.
      expect(itemsOf(calls.last), containsAllInOrder(['paste', 'Select All']));
      final rect = (calls.last.arguments as Map)['targetRect'] as Map;
      expect([rect['width'], rect['height']], everyElement(isNonNegative));
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(find.text('Paste'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a selection offers Cut, Copy, Paste and Select All; leaving the page hides the menu', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      note(tester).select(const TextSelection(baseOffset: 4, extentOffset: 8));
      await tester.pump();
      iosControls(tester).showToolbar();
      await tester.pumpAndSettle();
      expect(methods(calls), ['showSystemContextMenu']);
      expect(itemsOf(calls.last), ['Cut', 'Copy', 'paste', 'Select All', 'lookUp', 'searchWeb', 'share']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsNothing);
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a tap on the cursor opens the menu and a second tap closes it; a tap elsewhere moves the cursor', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      final at = note(tester).selection.baseOffset;
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(methods(calls), ['showSystemContextMenu']);
      expect(itemsOf(calls.last), contains('paste'));
      expect(note(tester).selection, TextSelection.collapsed(offset: at));
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
      // Elsewhere: the cursor moves to the last line, and no menu shows.
      await tester.tapAt(onLine(tester, 'Call Sam', 200));
      await tester.pump(const Duration(seconds: 1));
      expect(note(tester).selection.baseOffset, words.length);
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
      expect(editorFocused(tester), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the system hiding the menu tells the editor; the tap that hid it opens nothing, a later tap opens it',
        (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(toolbarShown(tester), isTrue);
      // On an iPhone a touch outside the menu closes it at touch down, then the tap up comes on the cursor.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(SystemChannels.platform.name,
        SystemChannels.platform.codec.encodeMethodCall(const MethodCall('ContextMenu.onDismissSystemContextMenu')), (_) {});
      await tester.tapAt(cursorAt(tester));
      await tester.pump();
      expect(toolbarShown(tester), isFalse);
      expect(methods(calls), ['showSystemContextMenu']);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(toolbarShown(tester), isTrue);
      expect(methods(calls), ['showSystemContextMenu', 'showSystemContextMenu']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a selection made backwards from the words into the title points the menu above the title', (tester) async {
      relay.entries = [Entry(id: 'n1', text: '# Shopping list\n$words', at: now)];
      final calls = menuCalls(tester);
      await editNote(tester, open: 'Shopping list');
      note(tester).select(const TextSelection(baseOffset: 30, extentOffset: 2));
      await tester.pump();
      iosControls(tester).showToolbar();
      await tester.pumpAndSettle();
      final title = find.text('Shopping list', findRichText: true).last;
      expect(kindOf(note(tester).nodes.first), LineKind.header1);
      final rect = (calls.last.arguments as Map)['targetRect'] as Map;
      expect(rect['y'] as double, lessThan(tester.getCenter(title).dy));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a tap on a link while editing puts the cursor in it and opens nothing', (tester) async {
      final opened = <Uri>[];
      menuCalls(tester);
      systemMenuOn(tester, true);
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk and eggs'));
      await tester.pumpAndSettle();
      await tester.tapAt(onLine(tester, 'Call Sam', 10));
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(onLine(tester, 'https://example.com/list', 40));
      await tester.pump(const Duration(seconds: 1));
      final link = words.indexOf('https://');
      expect(opened, isEmpty);
      expect(note(tester).selection.baseOffset, inInclusiveRange(link, link + 'https://example.com/list'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Select All selects every word and opens the menu again with Copy, which copies them', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      await tester.longPressAt(onLine(tester, 'Buy milk and eggs', 30));
      await tester.pumpAndSettle();
      expect(itemsOf(calls.last), contains('Select All'));
      await pressItem(tester, calls, 'Select All');
      final all = note(tester).text;
      expect(note(tester).selection, TextSelection(baseOffset: 0, extentOffset: all.length - 1));
      expect(methods(calls).last, 'showSystemContextMenu');
      expect(itemsOf(calls.last), containsAll(['Cut', 'Copy']));
      final copied = <Object?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text']);
        if (call.method.startsWith('ContextMenu.')) calls.add(call);
        return null;
      });
      await pressItem(tester, calls, 'Copy');
      expect(copied.last, words);
      await tester.pump(NoteSystemMenu.closeWindow);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('when the app does not take a paste, the plain words the system pastes come in at the cursor',
        (tester) async {
      menuCalls(tester);
      await editNote(tester);
      // The words the editor gave the keyboard, and the place of the cursor in them.
      final ime = (find.byType(SuperEditorImeInteractor).evaluate().first as StatefulElement).state as ImeInputOwner;
      final value = ime.imeClient.currentTextEditingValue!;
      final text = value.text, at = value.selection.baseOffset;
      ime.imeClient.updateEditingValueWithDeltas([TextEditingDeltaInsertion(oldText: text,
        textInserted: ' Buy oat milk', insertionOffset: at, selection: TextSelection.collapsed(offset: at + 13),
        composing: TextRange.empty)]);
      await tester.pump();
      expect(note(tester).text, startsWith('Buy milk and eggs Buy oat milk\n'));
      expect(stored(tester).split('\n').first, '# Buy milk and eggs Buy oat milk', reason: 'the words take no style');
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  });

  testWidgets('a hold and a drag show the magnifier, which goes when the finger lifts', (tester) async {
    menuCalls(tester);
    await editNote(tester);
    final gesture = await tester.startGesture(onLine(tester, 'Buy milk and eggs', 40));
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveTo(Offset(2, tester.getCenter(find.text('Buy milk and eggs', findRichText: true)).dy));
    await tester.pump();
    expect(iosControls(tester).shouldShowMagnifier.value, isTrue);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(iosControls(tester).shouldShowMagnifier.value, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  group('a paste keeps its formatting', () {
    const list = '<p>Fresh <b>bread</b></p><ul><li>Jam</li><li><i>Tea</i></li></ul>';

    testWidgets('the iPhone\'s own Paste puts styled words at the cursor and says it did', (tester) async {
      await editNote(tester);
      note(tester).select(const TextSelection(baseOffset: 43, extentOffset: 51));
      await tester.pump();
      expect(await phonePaste(tester, html: list, plain: 'Fresh bread\nJam\nTea'), isTrue);
      expect(stored(tester), '# Buy milk and eggs\nhttps://example.com/list\nFresh **bread**\n* Jam\n* _Tea_');
      expect(note(tester).selection, const TextSelection.collapsed(offset: 43 + 'Fresh bread\nJam\nTea'.length));
    });

    testWidgets('a few words join the line at the cursor, which keeps its style', (tester) async {
      await editNote(tester);
      note(tester).select(const TextSelection.collapsed(offset: 4));
      await tester.pump();
      expect(await phonePaste(tester, plain: 'oat '), isTrue);
      expect(stored(tester), '# Buy oat milk and eggs\nhttps://example.com/list\nCall Sam');
      expect(note(tester).selection, const TextSelection.collapsed(offset: 8));
    });

    testWidgets('words pasted beside a photo go on a line of their own, kept in the note, and one Undo takes them back',
        (tester) async {
      const photo = EntryFile(id: 'p1', name: 'receipt.jpg', type: 'image/jpeg', size: 1);
      const text = '# Desk lamp\n![receipt.jpg](attachment:p1)\nPaid';
      relay.entries = [Entry(id: 'n1', text: text, at: now, files: const [photo])];
      systemMenuOn(tester, true);
      await tester.pumpWidget(RelayApp(relay: relay, opener: (_) async => true));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Desk lamp').first);
      await tester.pumpAndSettle();
      await tester.tapAt(onLine(tester, 'Paid', 10));
      await tester.pump(const Duration(seconds: 1));
      expect(editorFocused(tester), isTrue);
      final before = note(tester).nodes;
      // The photo is at 10 and its line ends at 11: the cursor after the photo.
      note(tester).select(const TextSelection.collapsed(offset: 11));
      await tester.pump();
      expect(await phonePaste(tester, plain: 'in cash'), isTrue);
      expect(stored(tester), '# Desk lamp\n![receipt.jpg](attachment:p1)\nin cash\nPaid');
      expect(note(tester).selection, const TextSelection.collapsed(offset: 12 + 'in cash'.length));
      note(tester).undo();
      await tester.pump();
      expect(note(tester).nodes, before);
      note(tester).select(const TextSelection.collapsed(offset: 10));
      await tester.pump();
      await phonePaste(tester, plain: 'Shop');
      expect(stored(tester), '# Desk lamp\nShop\n![receipt.jpg](attachment:p1)\nPaid');
      expect(note(tester).selection, const TextSelection.collapsed(offset: 10 + 'Shop'.length));
    });

    testWidgets('one Undo takes back the whole paste', (tester) async {
      await editNote(tester);
      final before = note(tester).nodes;
      note(tester).select(const TextSelection(baseOffset: 43, extentOffset: 51));
      await tester.pump();
      await phonePaste(tester, plain: '\n## Plan\n- [ ] Call the bank\n- Buy **oat** milk\n');
      expect(stored(tester), endsWith('list\n## Plan\n- [ ] Call the bank\n- Buy **oat** milk'));
      note(tester).undo();
      await tester.pump();
      expect(note(tester).nodes, before);
    });

    testWidgets('with no note being edited, the app says no, so the phone pastes the plain words', (tester) async {
      await editNote(tester);
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isFalse);
      expect(await phonePaste(tester, html: list, plain: 'Fresh bread'), isFalse);
      expect(stored(tester), '# $words');
    });

    testWidgets('a copy from inside the note pastes back with its styles', (tester) async {
      String? copied;
      plainClipboard(tester, () => copied ?? '', onCopy: (text) => copied = text);
      await editNote(tester);
      final controller = note(tester);
      controller.select(const TextSelection(baseOffset: 43, extentOffset: 47));
      NoteCommands(controller).toggle(boldAttribution);
      controller.select(const TextSelection(baseOffset: 43, extentOffset: 51));
      await controlKey(tester, LogicalKeyboardKey.keyC);
      expect(copied, 'Call Sam');
      controller.select(const TextSelection.collapsed(offset: 17));
      await tester.pump();
      expect(await phonePaste(tester, plain: 'Call Sam'), isTrue);
      expect(stored(tester).split('\n').first, '# Buy milk and eggs**Call** Sam');
    });

    testWidgets('a table copied in the note pastes as a table of its own: a cell typed in the copy leaves the first',
        (tester) async {
      String? copied;
      plainClipboard(tester, () => copied ?? '', onCopy: (text) => copied = text);
      relay.entries = [Entry(id: 'n1', text: 'Plan\n| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\nEnd\n', at: now)];
      systemMenuOn(tester, true);
      await tester.pumpWidget(RelayApp(relay: relay, opener: (_) async => true));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Plan').first);
      await tester.pumpAndSettle();
      await tester.tapAt(onLine(tester, 'End', 10));
      await tester.pump(const Duration(seconds: 1));
      expect(editorFocused(tester), isTrue);
      final controller = note(tester);
      // The table, after `Plan\n`, to the start of the line under it.
      controller.select(const TextSelection(baseOffset: 5, extentOffset: 7));
      await controlKey(tester, LogicalKeyboardKey.keyC);
      // The empty last line.
      final end = controller.text.length - 1;
      controller.select(TextSelection.collapsed(offset: end));
      await tester.pump();
      expect(await phonePaste(tester, plain: copied!), isTrue);
      await tester.pumpAndSettle();
      final cells = find.descendant(of: find.byType(NoteTableView), matching: find.byType(TextField));
      expect(cells, findsNWidgets(8));
      await tester.tap(cells.at(4));
      await tester.pumpAndSettle();
      await tester.enterText(cells.at(4), 'Week');
      await tester.pump(cellPause);
      await tester.pumpAndSettle();
      expect(stored(tester), '# Plan\n| Day | Train |\n| --- | --- |\n| Mon | 9:00 |\nEnd\n'
        '| Week | Train |\n| --- | --- |\n| Mon | 9:00 |\n');
      expect([for (final cell in cells.evaluate()) (cell.widget as TextField).controller!.text],
        ['Day', 'Train', 'Mon', '9:00', 'Week', 'Train', 'Mon', '9:00']);
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
    });

    testWidgets('the app\'s own Paste reads the clipboard\'s HTML and keeps only the note\'s styles', (tester) async {
      htmlClipboard(tester, '<h5 style="color:red">Plan</h5><ol><li><span style="font-size:30px">Wake</span></li></ol>');
      plainClipboard(tester, () => 'Plan\nWake');
      await editNote(tester, systemMenu: false);
      note(tester).select(const TextSelection(baseOffset: 43, extentOffset: 51));
      await tester.pump();
      await controlKey(tester, LogicalKeyboardKey.keyV);
      await tester.pumpAndSettle();
      expect(stored(tester), '# Buy milk and eggs\nhttps://example.com/list\n### Plan\n1. Wake');
      note(tester).undo();
      await tester.pump();
      expect(stored(tester), '# $words');
    });
  });

  testWidgets('where the system menu can\'t show, the app draws its own menu with Paste and Select All', (tester) async {
    final calls = menuCalls(tester);
    await editNote(tester, systemMenu: false);
    await tester.tapAt(cursorAt(tester));
    await tester.pumpAndSettle();
    expect([find.text('Paste'), find.text('Select All')], everyElement(findsOneWidget));
    expect(calls, isEmpty);
    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();
    expect(note(tester).selection, const TextSelection(baseOffset: 0, extentOffset: words.length));
    expect([find.text('Cut'), find.text('Copy')], everyElement(findsOneWidget), reason: 'the menu opens again, as on the phone');
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
