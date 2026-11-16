// The editor's clipboard parts are experimental in flutter_quill; pubspec.lock pins them.
// ignore_for_file: experimental_member_use

import 'package:flutter/cupertino.dart' show CupertinoMagnifier, CupertinoTheme;
import 'package:flutter/foundation.dart' show Uint8List, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/internal.dart' show ClipboardService, ClipboardServiceProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/editor/markdown.dart';
import 'package:relay_app/editor/system_menu.dart';
import 'package:relay_app/editor/table.dart' show NoteTableView, cellPause;
import 'package:relay_app/relay.dart' show Entry;
import 'package:relay_app/screens/note_editor.dart';

import 'screens_test.dart' show FakeRelay, editorFocused, now, openFolder, quill;

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

QuillRawEditorState rawEditor(WidgetTester tester) => tester.state<QuillRawEditorState>(find.byType(QuillRawEditor));

/// The screen point of the blinking cursor.
Offset cursorAt(WidgetTester tester) {
  final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
  return editor.localToGlobal(editor.getLocalRectForCaret(quill(tester).selection.extent).center);
}

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

/// A clipboard that holds [html], as a page's copy does.
class HtmlClipboard extends ClipboardService {
  HtmlClipboard(this.html);

  final String html;

  @override
  Future<String?> getHtmlText() async => html;
  @override
  Future<String?> getHtmlFile() async => null;
  @override
  Future<String?> getMarkdownFile() async => null;
  @override
  Future<Uint8List?> getImageFile() async => null;
  @override
  Future<Uint8List?> getGifFile() async => null;
  @override
  Future<void> copyImage(Uint8List imageBytes) async {}
}

/// The note's words as it stores them.
String stored(WidgetTester tester) => deltaToMarkdown(quill(tester).document.toDelta());

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
    quill(tester).updateSelection(const TextSelection.collapsed(offset: 17), ChangeSource.local);
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
      expect(quill(tester).selection.isCollapsed, isTrue);
      expect(itemsOf(calls.last), ['paste', 'Select All']);
      final rect = (calls.last.arguments as Map)['targetRect'] as Map;
      expect([rect['width'], rect['height']], everyElement(isNonNegative));
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
      expect(find.text('Paste'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a selection offers Cut, Copy, Paste and Select All; leaving the page hides the menu', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      quill(tester).updateSelection(const TextSelection(baseOffset: 4, extentOffset: 8), ChangeSource.local);
      await tester.pump();
      rawEditor(tester).showToolbar();
      await tester.pumpAndSettle();
      expect(methods(calls), ['showSystemContextMenu']);
      expect(itemsOf(calls.last), ['Cut', 'Copy', 'paste', 'Select All']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsNothing);
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a tap on the cursor opens the menu and a second tap closes it; a tap elsewhere moves the cursor', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      final at = quill(tester).selection.baseOffset;
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(methods(calls), ['showSystemContextMenu']);
      expect(itemsOf(calls.last), contains('paste'));
      expect(quill(tester).selection, TextSelection.collapsed(offset: at));
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
      // Elsewhere: the cursor moves to the last line, and no menu shows.
      await tester.tapAt(onLine(tester, 'Call Sam', 200));
      await tester.pump(const Duration(seconds: 1));
      expect(quill(tester).selection.baseOffset, words.length);
      expect(methods(calls), ['showSystemContextMenu', 'hideSystemContextMenu']);
      expect(editorFocused(tester), isTrue);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('the system hiding the menu tells the editor; the tap that hid it opens nothing, a later tap opens it',
        (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(rawEditor(tester).selectionOverlay?.toolbar, isNotNull);
      // On an iPhone a touch outside the menu closes it at touch down, then the tap up comes on the cursor.
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(SystemChannels.platform.name,
        SystemChannels.platform.codec.encodeMethodCall(const MethodCall('ContextMenu.onDismissSystemContextMenu')), (_) {});
      await tester.tapAt(cursorAt(tester));
      await tester.pump();
      expect(rawEditor(tester).selectionOverlay?.toolbar, isNull);
      expect(methods(calls), ['showSystemContextMenu']);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(cursorAt(tester));
      await tester.pump(const Duration(seconds: 1));
      expect(rawEditor(tester).selectionOverlay?.toolbar, isNotNull);
      expect(methods(calls), ['showSystemContextMenu', 'showSystemContextMenu']);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('a selection made backwards from the words into the title points the menu above the title', (tester) async {
      relay.entries = [Entry(id: 'n1', text: '# Shopping list\n$words', at: now)];
      menuCalls(tester);
      await editNote(tester, open: 'Shopping list');
      quill(tester).updateSelection(const TextSelection(baseOffset: 30, extentOffset: 2), ChangeSource.local);
      await tester.pump();
      final title = find.text('Shopping list', findRichText: true).last;
      expect(quill(tester).document.toDelta().toList().firstWhere((op) => op.data == '\n').attributes, {'header': 1});
      expect(QuillSystemMenu.anchorOf(rawEditor(tester)).top, lessThanOrEqualTo(tester.getTopLeft(title).dy));
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
      expect(quill(tester).selection.baseOffset, inInclusiveRange(link, link + 'https://example.com/list'.length));
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('Select All selects every word and opens the menu again with Copy, which copies them', (tester) async {
      final calls = menuCalls(tester);
      await editNote(tester);
      await tester.longPressAt(onLine(tester, 'Buy milk and eggs', 30));
      await tester.pumpAndSettle();
      expect(itemsOf(calls.last), contains('Select All'));
      await pressItem(tester, calls, 'Select All');
      final all = rawEditor(tester).textEditingValue;
      expect(all.selection, TextSelection(baseOffset: 0, extentOffset: all.text.length - 1));
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
      await tester.pump(QuillSystemMenu.closeWindow);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

    testWidgets('when the app does not take a paste, the plain words the system pastes come in at the cursor',
        (tester) async {
      menuCalls(tester);
      await editNote(tester);
      final before = rawEditor(tester).textEditingValue;
      final at = before.selection.baseOffset;
      tester.testTextInput.updateEditingValue(before.copyWith(
        text: before.text.replaceRange(at, at, ' Buy oat milk'),
        selection: TextSelection.collapsed(offset: at + ' Buy oat milk'.length)));
      await tester.pump();
      final document = quill(tester).document;
      expect(document.toPlainText(), startsWith('Buy milk and eggs Buy oat milk\n'));
      final pasted = document.toDelta().toList().firstWhere((op) => '${op.data}'.contains('oat'));
      expect(pasted.attributes, isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  });

  testWidgets('a drag shows the phone\'s own magnifier, inside the screen near its left edge', (tester) async {
    menuCalls(tester);
    await editNote(tester);
    final cupertino = defaultTargetPlatform == TargetPlatform.iOS;
    final lens = cupertino ? find.byType(CupertinoMagnifier) : find.byType(Magnifier);
    final gesture = await tester.startGesture(onLine(tester, 'Buy milk and eggs', 40));
    await tester.pump(const Duration(seconds: 1));
    await gesture.moveTo(Offset(2, tester.getCenter(find.text('Buy milk and eggs', findRichText: true)).dy));
    await tester.pump();
    await tester.pump();
    expect(lens, findsOneWidget);
    expect(find.byType(cupertino ? Magnifier : CupertinoMagnifier), findsNothing);
    if (cupertino) {
      // The rim takes the app's tint, not Flutter's fixed blue, as the iPhone's own lens does.
      expect(tester.widget<CupertinoMagnifier>(lens).borderSide.color,
        CupertinoTheme.of(tester.element(find.byType(QuillEditor))).primaryColor);
    }
    final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
    final rect = tester.getRect(lens);
    expect([rect.left, rect.top], everyElement(isNonNegative));
    expect([rect.right <= screen.right, rect.bottom <= screen.bottom], [true, true]);
    await gesture.up();
    // Quill hides its magnifier a frame after the finger lifts.
    await tester.pump();
    await tester.pump();
    expect(lens, findsNothing);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));

  group('a paste keeps its formatting', () {
    const list = '<p>Fresh <b>bread</b></p><ul><li>Jam</li><li><i>Tea</i></li></ul>';

    testWidgets('the iPhone\'s own Paste puts styled words at the cursor and says it did', (tester) async {
      await editNote(tester);
      quill(tester).updateSelection(const TextSelection(baseOffset: 43, extentOffset: 51), ChangeSource.local);
      await tester.pump();
      expect(await phonePaste(tester, html: list, plain: 'Fresh bread\nJam\nTea'), isTrue);
      expect(stored(tester), '# Buy milk and eggs\nhttps://example.com/list\nFresh **bread**\n* Jam\n* _Tea_');
      expect(quill(tester).selection, const TextSelection.collapsed(offset: 43 + 'Fresh bread\nJam\nTea'.length));
    });

    testWidgets('a few words join the line at the cursor, which keeps its style', (tester) async {
      await editNote(tester);
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 4), ChangeSource.local);
      await tester.pump();
      expect(await phonePaste(tester, plain: 'oat '), isTrue);
      expect(stored(tester), '# Buy oat milk and eggs\nhttps://example.com/list\nCall Sam');
      expect(quill(tester).selection, const TextSelection.collapsed(offset: 8));
    });

    testWidgets('one Undo takes back the whole paste', (tester) async {
      await editNote(tester);
      final before = quill(tester).document.toDelta();
      quill(tester).updateSelection(const TextSelection(baseOffset: 43, extentOffset: 51), ChangeSource.local);
      await tester.pump();
      await phonePaste(tester, plain: '\n## Plan\n- [ ] Call the bank\n- Buy **oat** milk\n');
      expect(stored(tester), endsWith('list\n## Plan\n- [ ] Call the bank\n- Buy **oat** milk'));
      quill(tester).undo();
      await tester.pump();
      expect(quill(tester).document.toDelta(), before);
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
      final controller = quill(tester);
      controller.formatText(43, 4, Attribute.bold);
      controller.updateSelection(const TextSelection(baseOffset: 43, extentOffset: 51), ChangeSource.local);
      controller.clipboardSelection(true);
      await tester.pump();
      expect(copied, 'Call Sam');
      controller.updateSelection(const TextSelection.collapsed(offset: 17), ChangeSource.local);
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
      final controller = quill(tester);
      // The table and its line: one embed and a line break, after `Plan\n`.
      controller.updateSelection(const TextSelection(baseOffset: 5, extentOffset: 7), ChangeSource.local);
      controller.clipboardSelection(true);
      await tester.pump();
      // The empty last line.
      final end = controller.document.length - 1;
      controller.updateSelection(TextSelection.collapsed(offset: end), ChangeSource.local);
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
      ClipboardServiceProvider.setInstance(HtmlClipboard('<h5 style="color:red">Plan</h5><ol><li>'
        '<span style="font-size:30px">Wake</span></li></ol>'));
      addTearDown(ClipboardServiceProvider.setInstanceToDefault);
      plainClipboard(tester, () => 'Plan\nWake');
      await editNote(tester, systemMenu: false);
      quill(tester).updateSelection(const TextSelection(baseOffset: 43, extentOffset: 51), ChangeSource.local);
      await tester.pump();
      await rawEditor(tester).pasteText(SelectionChangedCause.keyboard);
      await tester.pump();
      expect(stored(tester), '# Buy milk and eggs\nhttps://example.com/list\n### Plan\n1. Wake');
      quill(tester).undo();
      await tester.pump();
      expect(stored(tester), '# $words');
    });
  });

  testWidgets('where the system menu can\'t show, the app draws its own menu with Paste', (tester) async {
    final calls = menuCalls(tester);
    await editNote(tester, systemMenu: false);
    await tester.tapAt(cursorAt(tester));
    await tester.pumpAndSettle();
    expect(find.text('Paste'), findsOneWidget);
    expect(calls, isEmpty);
  }, variant: const TargetPlatformVariant({TargetPlatform.iOS, TargetPlatform.android}));
}
