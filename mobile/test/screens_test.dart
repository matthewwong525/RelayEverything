import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction, RenderParagraph, SemanticsAction;
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/editor/markdown.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/connect.dart';
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/screens/folder.dart';
import 'package:relay_app/screens/note_bars.dart';
import 'package:relay_app/screens/note_editor.dart';
import 'package:relay_app/screens/round_button.dart' show ButtonPill;
import 'package:relay_app/screens/settings.dart' show SettingsScreen;
import 'package:relay_app/screens/timeline.dart' show TimelineScreen;

class FakeRelay extends Relay {
  @override bool connected = false;
  @override String? server;
  @override List<Entry> entries = [];
  @override SyncStatus status = SyncStatus.synced;
  @override int waiting = 0;
  @override Settings settings = const Settings();
  @override SendState healthSent = const SendState();
  @override SendState pointsSent = const SendState();
  @override SendState calendarSent = const SendState();
  @override List<PhoneCalendar> calendars = const [PhoneCalendar(id: 'work', name: 'Work', account: 'sam@example.com'),
    PhoneCalendar(id: 'holidays', name: 'US Holidays')];
  @override bool locationModes = false;
  @override Connections? connections;
  /// How many times a screen asked for [connections]; the fake answers nothing.
  int refreshes = 0;
  @override Set<String> folded = {};
  final calls = <String>[];
  String? problem;
  int earlier = 0;

  void changed() => notifyListeners();

  @override
  Future<void> refreshConnections() async {
    refreshes++;
  }

  @override
  Future<void> setFolded(String header, bool folded) async {
    calls.add('fold $header $folded');
    this.folded = folded ? {...this.folded, header} : ({...this.folded}..remove(header));
    notifyListeners();
  }

  @override
  Future<String?> connect(String code) async {
    calls.add('connect $code');
    if (problem == null) {
      connected = true;
      notifyListeners();
    }
    return problem;
  }

  /// Null: the person closed the sign-in, so no key is kept.
  bool signsIn = true;

  @override
  Future<String?> signIn(String server) async {
    calls.add('sign in $server');
    if (problem == null && signsIn) {
      connected = true;
      notifyListeners();
    }
    return problem;
  }

  @override
  Future<String?> setLocationMode(LocationMode mode) async {
    calls.add('mode ${mode.name}');
    settings = settings.copyWith(mode: mode);
    notifyListeners();
    return problem;
  }

  @override Future<String?> setServer(String server) async { calls.add('server $server'); return problem; }
  @override Future<String?> setPinNotes(bool on) async { calls.add('pin $on'); return problem; }

  @override
  Future<void> setAppearance(Appearance appearance) async {
    calls.add('appearance ${appearance.name}');
    settings = settings.copyWith(appearance: appearance);
    notifyListeners();
  }
  @override Future<String?> setHistory(bool on) async { calls.add('history $on'); return problem; }
  @override Future<String?> setHealth(bool on) async { calls.add('health $on'); return problem; }
  @override Future<String?> setPhotos(bool on) async { calls.add('photos $on'); return problem; }
  @override Future<String?> setPhotosOnMobileData(bool on) async { calls.add('mobile data $on'); return problem; }
  @override Future<String?> setCalendar(bool on) async { calls.add('calendar $on'); return problem; }

  @override
  Future<void> setCalendarShown(String id, bool on) async {
    calls.add('calendar $id $on');
    final off = {...settings.calendarsOff};
    on ? off.remove(id) : off.add(id);
    settings = settings.copyWith(calendarsOff: off);
    notifyListeners();
  }
  @override Future<int> earlierNotes() async => earlier;

  @override
  Future<String?> startSending({required bool sendEarlier, SendPlace? place}) async {
    calls.add('start $sendEarlier${place == SendPlace.webhook ? ' webhook' : ''}');
    settings = settings.copyWith(sending: true, place: place);
    notifyListeners();
    return null;
  }

  @override String? webhookAddress;
  @override String? webhookSecret;
  @override WebhookProblem? webhookProblem;
  @override String newWebhookSecret() => 'whsec_bmV3LXNlY3JldC1mb3ItYS10ZXN0LW9ubHk=';
  /// What [testWebhook] answers.
  String testAnswer = 'Your receiver answered 204. It works.';

  @override
  Future<String?> saveWebhook(String address, String secret) async {
    calls.add('webhook $address $secret');
    if (problem == null) {
      webhookAddress = address;
      webhookSecret = secret;
    }
    return problem;
  }

  @override
  Future<String> testWebhook(String address, String secret) async {
    calls.add('test $address');
    return testAnswer;
  }

  @override
  Future<void> stopSending() async {
    calls.add('stop');
    settings = settings.copyWith(sending: false);
    notifyListeners();
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    connected = false;
    settings = settings.copyWith(sending: false);
    notifyListeners();
  }

  @override Future<void> sync() async => calls.add('sync');
  @override Future<void> pullNotes() async => calls.add('pull');

  /// While set, each add and change waits for it, as a slow phone store does.
  Completer<void>? slow;
  /// What [addNote] answers when it keeps nothing, such as for a file over 25 MB alone.
  String? keepsNothing;

  @override
  Future<String?> addNote(String text, {List<NewFile> files = const [], String? id, bool sendNow = true}) async {
    calls.add('note $text${_names(files)}${sendNow ? '' : ' (later)'}');
    await slow?.future;
    if (keepsNothing != null) return keepsNothing;
    entries = [Entry(id: id ?? '', text: text, at: DateTime.now()), ...entries];
    notifyListeners();
    return null;
  }

  @override
  Future<String?> editNote(String id, String text, {List<NewFile> files = const [], bool sendNow = true}) async {
    calls.add('edit $text${_names(files)}${sendNow ? '' : ' (later)'}');
    await slow?.future;
    return null;
  }

  /// A sent note is deleted everywhere, with *Undo*, as the controller does; a note never sent is dropped.
  @override
  Future<Emptied> dropEmptyNote(String id) async {
    calls.add('drop $id');
    final kept = entries.where((entry) => entry.id != id || entry.files.isNotEmpty || entry.voice).toList();
    if (kept.length == entries.length) return Emptied.kept;
    for (final entry in entries) {
      if (entry.id == id && entry.sent) deleted[id] = entry;
    }
    entries = kept;
    notifyListeners();
    return deleted.containsKey(id) ? Emptied.deleting : Emptied.dropped;
  }

  /// The notes deleted and not yet undone, so that [undoDelete] puts each back.
  final deleted = <String, Entry>{};

  @override
  Future<void> deleteNote(String id) async {
    calls.add('delete $id');
    for (final entry in entries) {
      if (entry.id == id) deleted[id] = entry;
    }
    entries = [for (final entry in entries) if (entry.id != id) entry];
    notifyListeners();
  }

  @override
  Future<void> undoDelete(String id) async {
    calls.add('undo $id');
    final entry = deleted.remove(id);
    if (entry != null) entries = [...entries, entry]..sort((a, b) => b.at.compareTo(a.at));
    notifyListeners();
  }

  @override
  Future<void> endUndo(String id) async {
    calls.add('end $id');
    deleted.remove(id);
  }

  static String _names(List<NewFile> files) => files.isEmpty ? '' : ' + ${[for (final file in files) file.name].join(', ')}';

  @override Future<void> openFile(EntryFile file) async => calls.add('open ${file.name}');

  @override ModelState speechModel = ModelState.ready;
  @override double modelProgress = 0;
  @override ModelProblem? modelProblem;
  @override int modelBytes = 59721011;
  @override DateTime? listening;
  /// What [startVoiceNote] and [endVoiceNote] return.
  String? startProblem;
  String? endProblem;

  @override
  void askSpeechModel() {
    calls.add('ask model');
    speechModel = ModelState.asking;
  }

  @override
  void notNowSpeechModel() {
    calls.add('not now');
    speechModel = ModelState.missing;
    notifyListeners();
  }

  @override
  Future<void> getSpeechModel() async {
    calls.add('get model');
    speechModel = ModelState.downloading;
    modelProgress = 0.4;
    notifyListeners();
  }

  @override
  Future<void> removeSpeechModel() async {
    calls.add('remove model');
    speechModel = ModelState.missing;
    notifyListeners();
  }

  @override
  Future<String?> startVoiceNote() async {
    calls.add('voice start');
    if (startProblem == null) {
      listening = DateTime.now();
      notifyListeners();
    }
    return startProblem;
  }

  @override
  Future<String?> endVoiceNote() async {
    calls.add('voice end');
    listening = null;
    notifyListeners();
    return endProblem;
  }

  @override
  Future<void> cancelVoiceNote() async {
    calls.add('voice cancel');
    listening = null;
    notifyListeners();
  }

  @override Future<void> play(String recording) async => calls.add('play $recording');
  @override Future<void> writeWordsAgain() async => calls.add('words again');
}

final now = DateTime.now();

/// The round *New note* button: a tap writes, a hold talks.
final newNote = find.byType(NewNoteButton);

/// Opens Settings with Home's gear.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

/// Scrolls Home until the folder row [title] sits mid-screen, clear of the dock, and opens it.
Future<void> openFolder(WidgetTester tester, String title) async {
  final row = find.widgetWithText(ListTile, title);
  await tester.scrollUntilVisible(row, 100, scrollable: find.byType(Scrollable).first);
  await Scrollable.ensureVisible(tester.element(row), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

/// A screen tall enough that all of Home is built at once.
void tallScreen(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The count a Home row shows at its right, such as *6* beside *Notes*.
Finder countOn(String title, int count) => find.descendant(of: find.widgetWithText(ListTile, title), matching: find.text('$count'));

/// Holds *New note* until it turns into the mic, then lets go: the phone keeps listening.
Future<void> holdNewNote(WidgetTester tester) async {
  final gesture = await tester.startGesture(tester.getCenter(newNote));
  await tester.pump(holdToTalk);
  await tester.pump();
  await gesture.up();
  await tester.pump();
}

/// A tap on the screen away from the card, which saves the voice note.
Future<void> tapAnywhere(WidgetTester tester) async {
  await tester.tapAt(const Offset(200, 150));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The fill and the word color of a [BrandTag].
(Color?, Color?) tagColors(WidgetTester tester, String label) {
  final tag = find.widgetWithText(BrandTag, label).first;
  final box = tester.widget<DecoratedBox>(find.descendant(of: tag, matching: find.byType(DecoratedBox)).first);
  final ink = tester.renderObject<RenderParagraph>(find.descendant(of: tag, matching: find.text(label))).text.style?.color;
  return ((box.decoration as ShapeDecoration).color, ink);
}

/// How far *Sync now*'s arrows have turned, from 0 to 1.
double arrowsTurn() => find.ancestor(of: find.byIcon(CupertinoIcons.arrow_2_circlepath), matching: find.byType(RotationTransition))
  .evaluate().map((element) => (element.widget as RotationTransition).turns.value).first;

/// The note page's editor.
QuillController quill(WidgetTester tester) => tester.widget<QuillEditor>(find.byType(QuillEditor)).controller;

/// The note page's words as it keeps them.
String markdownOf(WidgetTester tester) => deltaToMarkdown(quill(tester).document.toDelta());

/// Whether the note page has the keyboard up.
bool editorFocused(WidgetTester tester) => tester.widget<QuillEditor>(find.byType(QuillEditor)).focusNode.hasFocus;

/// Types [words] at the cursor, as the keyboard does.
Future<void> type(WidgetTester tester, String words) async {
  final controller = quill(tester);
  final at = controller.selection.baseOffset;
  controller.replaceText(at, 0, words, TextSelection.collapsed(offset: at + words.length));
  await tester.pump();
}

/// The screen point [part] of the way across the note page's letter at [letter]: 0.8 is its right half.
Offset onLetter(WidgetTester tester, int letter, double part) {
  final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
  final left = editor.getLocalRectForCaret(TextPosition(offset: letter));
  final right = editor.getLocalRectForCaret(TextPosition(offset: letter + 1));
  return editor.localToGlobal(Offset(left.left + (right.left - left.left) * part, left.center.dy));
}

void main() {
  late FakeRelay relay;
  setUp(() {
    relay = FakeRelay();
    PackageInfo.setMockInitialValues(appName: 'Relay Everything', packageName: 'com.relayeverything.app', version: '1.4.0',
      buildNumber: '91', buildSignature: '');
  });

  /// Scrolls the connect screen's own list until [finder] shows.
  Future<void> scrollConnect(WidgetTester tester, Finder finder, [double delta = 100]) => tester.scrollUntilVisible(finder, delta,
    scrollable: find.descendant(of: find.byType(ConnectScreen), matching: find.byType(Scrollable)).first);

  SwitchListTile switchOf(WidgetTester tester, String title) => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

  testWidgets('shows the mark above the large Home title, in the brand colors that follow the phone', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byType(RelayMark)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Home')), findsWidgets);
    // The large title; the bar's small one shows only once the list scrolls under it.
    expect(tester.renderObjectList<RenderParagraph>(find.text('Home')).map((title) => title.text.style?.fontSize), contains(32));
    RelayMarkPainter painter() => tester.widget<CustomPaint>(
      find.descendant(of: find.byType(RelayMark).first, matching: find.byType(CustomPaint))).painter! as RelayMarkPainter;
    expect(painter().ink, BrandColors.light.accentText);
    expect(painter().spark, BrandColors.light.spark);
    expect(Theme.of(tester.element(bar)).scaffoldBackgroundColor, BrandColors.light.paper);

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(painter().ink, BrandColors.dark.accentText);
    expect(Theme.of(tester.element(bar)).scaffoldBackgroundColor, BrandColors.dark.paper);
  });

  testWidgets('opens on Home with no key: every folder at 0 or Off, and Notes keeps a note on this phone', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Where should the phone send?'), findsNothing);
    // The header, and the sync line: nothing leaves the phone.
    expect(find.text('On this phone'), findsNWidgets(2));
    for (final title in ['Notes', 'Voice notes', 'Shares']) {
      expect(countOn(title, 0), findsOneWidget, reason: title);
    }
    for (final title in ['Location', 'Health', 'Calendar']) {
      expect(find.descendant(of: find.widgetWithText(ListTile, title), matching: find.text('Off')), findsOneWidget, reason: title);
    }
    expect(find.text('Off: nothing leaves this phone'), findsOneWidget);
    expect(find.text('Sign in to see'), findsNWidgets(2));
    await openFolder(tester, 'Notes');
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Tap New note to write one, or hold it to talk.'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you turn on Sending on Home.'), findsOneWidget);
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    await type(tester, 'Buy milk');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, ['note # Buy milk']);
    relay
      ..entries = [Entry(text: 'Buy milk', at: now, place: 'Pinned')]
      ..changed();
    await tester.pump();
    expect(find.textContaining('Pinned'), findsOneWidget);
    expect(find.textContaining('Waiting to send'), findsNothing);
    expect(find.text('Today'), findsOneWidget);
  });

  testWidgets('turns sending on: connects a key first, then asks about earlier notes', (tester) async {
    relay.earlier = 42;
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));
    await openFolder(tester, 'Sending');
    expect(find.text('Disconnect this phone'), findsNothing);
    expect(find.text('Server'), findsNothing);
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    expect(find.text('Where should the phone send?'), findsOneWidget);
    // Back from the connect screen with no key: sending stays off.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'key');
    await scrollConnect(tester, find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Send your 42 earlier notes too?'), findsOneWidget);
    await tester.tap(find.text('Only new notes'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['connect key', 'start false']);
    expect(find.byType(SendingPage), findsOneWidget);
    expect(find.text('Disconnect this phone'), findsOneWidget);
  });

  testWidgets('turns sending on again with a key kept: asks, and sends earlier notes on a yes', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..earlier = 1;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Sending');
    expect(find.text('Off: nothing leaves this phone. On: to your Relay Everything server, or to your own webhook.'), findsOneWidget);
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    expect(find.text('This phone has a key for https://relay.example.com.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Send your earlier note too?'), findsOneWidget);
    await tester.tap(find.text('Send it'));
    await tester.pumpAndSettle();
    expect(find.textContaining('To Relay Everything: relay.example.com.'), findsOneWidget);
    relay.earlier = 0;
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sending?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(relay.settings.sending, isTrue);
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop sending'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['start true', 'stop']);
    // Off and on again with nothing earlier: no prompt.
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(relay.calls, ['start true', 'stop', 'start false']);
  });

  testWidgets('connects by a pasted key, and says why one is refused', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Sending');
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    relay.problem = 'That is not a Relay Everything key.';
    await tester.enterText(find.byType(TextField), 'nonsense');
    await scrollConnect(tester, find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    await scrollConnect(tester, find.text('That is not a Relay Everything key.'));
    relay.problem = null;
    await tester.ensureVisible(find.text('Connect'));
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['connect nonsense', 'connect nonsense', 'start false']);
    expect(find.byType(SendingPage), findsOneWidget);
  });

  testWidgets('connects by signing in, to the shared server or another, and stays open when the sign-in is closed', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Sending');
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    relay.signsIn = false;
    await tester.tap(find.text('Sign in to connect'));
    await tester.pumpAndSettle();
    expect(find.text('Where should the phone send?'), findsOneWidget);
    relay.problem = 'The server did not connect this phone. Sign in and try again.';
    await tester.tap(find.text('Use another server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'https://relay.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await scrollConnect(tester, find.text('The server did not connect this phone. Sign in and try again.'));
    await scrollConnect(tester, find.text('Sign in to connect'), -100);
    relay
      ..problem = null
      ..signsIn = true;
    await tester.tap(find.text('Sign in to connect'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sign in https://app.relayeverything.com', 'sign in https://relay.example.com',
      'sign in https://app.relayeverything.com', 'start false']);
    expect(find.byType(SendingPage), findsOneWidget);
  });

  testWidgets('connects by a scanned key, and does nothing when the scan is closed', (tester) async {
    String? scanned;
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => scanned));
    await openFolder(tester, 'Sending');
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan the QR code'));
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
    scanned = '{"relay":1}';
    await tester.tap(find.text('Scan the QR code'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['connect {"relay":1}', 'start false']);
  });

  testWidgets('shows each note with its kind, its place, and Sent or Waiting to send', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..waiting = 1
      ..entries = [
        Entry(text: 'Lunch idea', at: now, place: 'King St W', waiting: true),
        Entry(text: 'Buy 0.2 mm steel for the stiffener', at: DateTime(2026, 1, 2, 9), place: 'Harbord St', sent: true),
      ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(find.text('Typed'), findsNWidgets(2));
    expect(find.textContaining('King St W · Waiting to send'), findsOneWidget);
    expect(find.textContaining('Harbord St · Sent'), findsOneWidget);
    expect(find.textContaining('Jan 2'), findsOneWidget);
    expect(find.text('2 notes ·'), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
    await tester.tap(find.text('1 waiting'));
    expect(relay.calls, ['pull']);
  });

  testWidgets('the gear opens Settings in one tap, and Home has no ⋯ menu', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.byTooltip('More'), findsNothing);
    expect(find.byIcon(CupertinoIcons.gear), findsOneWidget);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(find.byType(MenuItemButton), findsNothing);
    expect(relay.calls, isEmpty);
  });

  testWidgets('Sync now follows the sync state while sending, and does what a pull down does', (tester) async {
    relay.entries = [Entry(text: 'Lunch idea', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('On this phone'), findsWidgets);
    expect(find.byTooltip('Sync now'), findsNothing);
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..waiting = 1
      ..changed();
    await tester.pump();
    final state = tester.getRect(find.text('1 waiting'));
    final button = tester.getRect(find.byTooltip('Sync now'));
    expect(button.left, greaterThan(state.right));
    expect((button.center.dy - state.center.dy).abs(), lessThan(2));
    expect([button.width, button.height], [32, 32]);
    // Muted, not the accent.
    expect(tester.widget<Icon>(find.byIcon(CupertinoIcons.arrow_2_circlepath)).color, BrandColors.light.muted);
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    await tester.drag(find.text('Voice notes'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pull', 'pull']);
    // A notes folder has its own, under its title.
    await openFolder(tester, 'Notes');
    await tester.tap(find.byTooltip('Sync now'));
    await tester.pump();
    expect(relay.calls, ['pull', 'pull', 'pull']);
  });

  testWidgets('Sending shows Open your Relay Everything page only while sending to a server, and it opens the page',
      (tester) async {
    tallScreen(tester);
    final opened = <Uri>[];
    var opens = true;
    relay
      ..connected = true
      ..server = 'https://relay.example.com';
    await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
      opened.add(address);
      return opens;
    }));
    await openFolder(tester, 'Sending');
    const row = 'Open your Relay Everything page';
    expect(find.text(row), findsNothing);
    relay
      ..settings = const Settings(sending: true, place: SendPlace.webhook)
      ..changed();
    await tester.pump();
    expect(find.text(row), findsNothing);
    relay
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.pump();
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://relay.example.com/apps/relay/')]);
    opens = false;
    await tester.tap(find.text(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The browser did not open. Try again.'), findsOneWidget);
    expect([opened, relay.calls], [hasLength(2), isEmpty]);
  });

  testWidgets('Light picked on a dark phone shows the light colors, and again after a new start', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(RelayApp(relay: relay));
    Color paper() => Theme.of(tester.element(find.byType(Scaffold).last)).scaffoldBackgroundColor;
    expect(paper(), BrandColors.dark.paper);
    await openSettings(tester);
    final segments = tester.widget<SegmentedButton<Appearance>>(find.byType(SegmentedButton<Appearance>));
    expect(segments.selected, {Appearance.system});
    await tester.tap(find.text('Light'));
    await tester.pumpAndSettle();
    expect([relay.calls, paper()], [['appearance light'], BrandColors.light.paper]);
    // A new start reads the pick the phone kept.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.pumpAndSettle();
    expect(paper(), BrandColors.light.paper);
    relay
      ..settings = relay.settings.copyWith(appearance: Appearance.dark)
      ..changed();
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpAndSettle();
    expect(paper(), BrandColors.dark.paper);
  });

  testWidgets('a swipe to the left deletes a note at once, and Undo in the bar brings it back', (tester) async {
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Buy milk'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(relay.calls, ['delete n1']);
    expect([find.text('Buy milk'), find.text('Call Sam'), find.text('Note deleted')], [findsNothing, findsOneWidget, findsOneWidget]);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['delete n1', 'undo n1']);
    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('the delete runs only once the Undo bar has closed, its five seconds counted from when it is in', (tester) async {
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Buy milk'), const Offset(-500, 0));
    for (var frame = 0; frame < 100 && relay.calls.isEmpty; frame++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(relay.calls, ['delete n1']);
    // Five seconds after the delete, the bar that slid in after it has had less than its five seconds: Undo still shows.
    for (var step = 0; step < 50; step++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect([relay.calls, find.text('Undo').evaluate().length], [['delete n1'], 1]);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect([relay.calls, find.text('Undo').evaluate()], [['delete n1', 'end n1'], isEmpty]);
  });

  testWidgets('a second delete closes the first bar, and the first delete runs once it is gone', (tester) async {
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Buy milk'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.text('Call Sam'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect([relay.calls, find.text('Note deleted').evaluate().length], [['delete n1', 'delete n2', 'end n1'], 1]);
  });

  testWidgets('a swipe to the right deletes nothing', (tester) async {
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Buy milk'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect([relay.calls, find.text('Buy milk').evaluate().length], [isEmpty, 1]);
  });

  testWidgets('with a screen reader, each note row has its own Delete action', (tester) async {
    final semantics = tester.ensureSemantics();
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(tester.getSemantics(find.text('Call Sam')),
      isSemantics(customActions: [const CustomSemanticsAction(label: 'Delete')]));
    tester.semantics.performAction(find.semantics.byLabel(RegExp('Call Sam')), SemanticsAction.customAction,
      args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Delete')));
    await tester.pumpAndSettle();
    expect(relay.calls, ['delete n2']);
    expect([find.text('Buy milk'), find.text('Call Sam'), find.text('Note deleted')], [findsOneWidget, findsNothing, findsOneWidget]);
    semantics.dispose();
  });

  testWidgets('lists a note by its words with no marks, and search skips the marks too', (tester) async {
    relay.entries = [Entry(text: '# Shop\n- [ ] Eggs\n* **Milk**', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(find.text('Shop'), findsOneWidget);
    expect(find.textContaining('Eggs Milk'), findsOneWidget);
    expect(find.textContaining('#'), findsNothing);
    await tester.enterText(find.byType(TextField), '# shop');
    await tester.pump();
    expect(find.text('Shop'), findsNothing);
  });

  testWidgets('groups notes by day, newest first, under Today, Yesterday and Previous 7 days', (tester) async {
    relay.entries = [
      Entry(text: 'Ask Sam if the trip moves', at: now),
      Entry(text: 'Paint colours for the hall\nthe warm grey, not the blue.', at: now.subtract(const Duration(days: 1))),
      Entry(text: 'Dentist moved to Thursday', at: now.subtract(const Duration(days: 4))),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    double top(String text) => tester.getTopLeft(find.text(text)).dy;
    expect([for (final heading in ['Today', 'Yesterday', 'Previous 7 days']) find.text(heading).evaluate().length], [1, 1, 1]);
    expect(top('Today') < top('Ask Sam if the trip moves'), isTrue);
    expect(top('Ask Sam if the trip moves') < top('Yesterday'), isTrue);
    expect(top('Yesterday') < top('Paint colours for the hall'), isTrue);
    expect(top('Paint colours for the hall') < top('Previous 7 days'), isTrue);
    expect(top('Previous 7 days') < top('Dentist moved to Thursday'), isTrue);
    // The first line is the row's title; the rest follows the time.
    expect(find.textContaining('the warm grey, not the blue.', findRichText: true), findsOneWidget);
  });

  testWidgets('New note is the only control filled with the accent color', (tester) async {
    relay.entries = [Entry(text: 'Spoken', at: now, voice: true), Entry(text: 'Written', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    final accent = [for (final material in tester.widgetList<Material>(find.byType(Material)))
      if (material.color == BrandColors.light.accent) material];
    expect(accent, hasLength(1));
    expect(find.descendant(of: newNote, matching: find.byWidget(accent.single)), findsOneWidget);
    expect(tester.widgetList(find.byType(FilledButton)), isEmpty);
  });

  testWidgets('search in Notes shows only the notes that hold the words, in any case; Cancel shows them all again',
      (tester) async {
    relay.entries = [
      Entry(text: 'Dentist moved to Thursday 3 pm', at: now),
      Entry(text: 'Paint colours for the hall', at: now, place: 'Home', files: const [
        EntryFile(name: 'swatches.pdf', type: 'application/pdf', size: 245760, path: '/nowhere/swatches.pdf')]),
      Entry(text: 'Gift ideas', at: now),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    final search = find.widgetWithText(TextField, 'Search');
    await tester.tap(search);
    await tester.pump();
    expect([find.text('Cancel'), newNote], [findsOneWidget, findsNothing]);
    await tester.enterText(search, 'DENTIST');
    await tester.pump();
    expect([find.text('Dentist moved to Thursday 3 pm'), find.text('Paint colours for the hall'), find.text('Gift ideas')],
      [findsOneWidget, findsNothing, findsNothing]);
    for (final words in ['home', 'Swatches']) {
      await tester.enterText(find.byType(TextField), words);
      await tester.pump();
      expect([find.text('Dentist moved to Thursday 3 pm'), find.text('Paint colours for the hall')], [findsNothing, findsOneWidget]);
    }
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No notes with "zzz"'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect([find.text('Gift ideas'), find.text('Dentist moved to Thursday 3 pm'), newNote, find.text('Cancel')],
      [findsOneWidget, findsOneWidget, findsOneWidget, findsNothing]);
    expect(relay.calls, isEmpty);
  });

  testWidgets('names each sync state while sending, and an empty timeline in words', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you turn on Sending on Home.'), findsNothing);
    expect(find.text('On this phone'), findsNothing);
    for (final (status, waiting, label) in [(SyncStatus.syncing, 0, 'Syncing'), (SyncStatus.refused, 0, 'Key refused'),
      (SyncStatus.offline, 0, 'Offline'), (SyncStatus.offline, 2, '2 waiting'), (SyncStatus.idle, 0, 'Synced')]) {
      relay
        ..status = status
        ..waiting = waiting
        ..changed();
      await tester.pump();
      expect(find.text(label), findsOneWidget, reason: label);
    }
    await tester.drag(find.text('No notes yet'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pull']);
  });

  testWidgets('the Syncing dot pulses, the Synced dot is still, and with reduced motion Syncing is still too', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..status = SyncStatus.syncing;
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.hasRunningAnimations, isTrue);
    relay
      ..status = SyncStatus.synced
      ..changed();
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    relay
      ..status = SyncStatus.syncing
      ..changed();
    await tester.pumpAndSettle();
    expect([find.text('Syncing').evaluate().length, tester.hasRunningAnimations], [1, false]);
    expect(arrowsTurn(), 0);
  });

  testWidgets('the Sync now arrows turn only while syncing', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    expect([tester.hasRunningAnimations, arrowsTurn()], [false, 0]);
    relay
      ..status = SyncStatus.syncing
      ..changed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(arrowsTurn(), greaterThan(0));
    relay
      ..status = SyncStatus.synced
      ..changed();
    await tester.pumpAndSettle();
    expect(arrowsTurn(), 0);
  });

  group('the note page', () {
    testWidgets('a new note opens with the keyboard up and a Title line, and leaving keeps it with no Save', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsNothing);
      expect(editorFocused(tester), isTrue);
      expect(quill(tester).document.toDelta().toJson(), [{'insert': '\n', 'attributes': {'header': 1}}]);
      await type(tester, 'Buy milk');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['note # Buy milk']);
      expect(find.byType(NoteEditor), findsNothing);
    });

    testWidgets('an empty new note adds nothing', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await type(tester, '   ');
      await tester.pump(const Duration(seconds: 2));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('a new note typed, kept on a pause, then emptied is deleted on leave, and its blank words never go', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await type(tester, 'Buy');
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['note # Buy (later)']);
      final id = relay.entries.single.id;
      quill(tester).replaceText(0, 3, '', const TextSelection.collapsed(offset: 0));
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['note # Buy (later)']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['note # Buy (later)', 'drop $id']);
      expect([relay.entries, find.text('Buy').evaluate()], [isEmpty, isEmpty]);
    });

    testWidgets('an old note emptied is deleted on leave', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      // With the keyboard down a change is kept at once: blank words are not.
      quill(tester).replaceText(0, 8, '', const TextSelection.collapsed(offset: 0));
      await tester.pump();
      expect(relay.calls, isEmpty);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['drop n1']);
      expect([find.text('Buy milk'), find.text('Call Sam')], [findsNothing, findsOneWidget]);
    });

    testWidgets('a sent note emptied is deleted on leave, with Note deleted and Undo on the list', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now, sent: true), Entry(id: 'n2', text: 'Call Sam', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      quill(tester).replaceText(0, 8, '', const TextSelection.collapsed(offset: 0));
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['drop n1']);
      expect([find.text('Buy milk'), find.text('Call Sam'), find.text('Note deleted'), find.text('Undo')],
        [findsNothing, findsOneWidget, findsOneWidget, findsOneWidget]);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect([relay.calls, find.text('Buy milk').evaluate().length], [['drop n1', 'undo n1'], 1]);
    });

    testWidgets('a voice note emptied keeps its recording, with no words', (tester) async {
      relay.entries = [Entry(id: 'v1', text: 'Hello there', at: now, voice: true, recording: 'voice/a.wav')];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Hello there'));
      await tester.pumpAndSettle();
      quill(tester).replaceText(0, 11, '', const TextSelection.collapsed(offset: 0));
      await tester.pump();
      expect(relay.calls, ['edit ']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([relay.calls, relay.entries.length], [['edit '], 1]);
    });

    testWidgets('typing keeps the words on a pause without sending, and leaving sends them', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await type(tester, 'Buy');
      await tester.pump(const Duration(seconds: 1));
      expect(relay.calls, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(relay.calls, ['note # Buy (later)']);
      await type(tester, ' milk');
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['note # Buy (later)', 'edit # Buy milk (later)']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['note # Buy (later)', 'edit # Buy milk (later)', 'sync']);
    });

    testWidgets('an add that kept nothing is tried again with the words typed after it', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay, picker: ({required photos}) async =>
        [const NewFile(path: '/picked/big.mov', name: 'big.mov', size: 30 << 20)]));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      relay.keepsNothing = 'big.mov is over 25 MB, so it was not added. Give the note words or a file.';
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['note  + big.mov (later)']);
      expect(find.textContaining('over 25 MB'), findsOneWidget);
      relay.keepsNothing = null;
      await type(tester, 'Buy milk');
      await tester.pump(const Duration(seconds: 2));
      await type(tester, ' and eggs');
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['note  + big.mov (later)', 'note # Buy milk (later)', 'edit # Buy milk and eggs (later)']);
    });

    testWidgets('leaving sends only after the save still being written', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 8), ChangeSource.local);
      relay.slow = Completer();
      await type(tester, ' now');
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['edit # Buy milk now (later)']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Buy milk now (later)']);
      relay.slow!.complete();
      await tester.pump();
      expect(relay.calls, ['edit # Buy milk now (later)', 'sync']);
    });

    testWidgets('an old note opened and left is not written back', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk\n* eggs', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isFalse);
      expect(find.byType(ReadingBar), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('a fixed word is kept, and the list shows it', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      quill(tester).replaceText(4, 4, 'oat milk', const TextSelection.collapsed(offset: 12));
      await tester.pump();
      // With the keyboard down a change is kept and sent at once.
      expect(relay.calls, ['edit # Buy oat milk']);
      relay
        ..entries = [Entry(id: 'n1', text: '# Buy oat milk', at: now)]
        ..changed();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Buy oat milk']);
      expect(find.text('Buy oat milk'), findsOneWidget);
    });

    testWidgets('Done closes the keyboard and shows the reading bar; compose opens a new note', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      expect([find.byType(FloatingToolBar), find.byTooltip('Done')], everyElement(findsOneWidget));
      await type(tester, 'Ideas');
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isFalse);
      expect([find.byType(FloatingToolBar), find.byTooltip('Done')], everyElement(findsNothing));
      expect(find.byType(ReadingBar), findsOneWidget);
      expect(relay.calls, ['note # Ideas']);
      await tester.tap(find.byTooltip('New note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(quill(tester).document.toPlainText(), '\n');
      expect(editorFocused(tester), isTrue);
    });

    testWidgets('Heading styles only the line with the cursor, and Bold only the words picked', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop\nEggs and milk', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 7), ChangeSource.local);
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pumpAndSettle();
      expect(find.byType(FormatSheet), findsOneWidget);
      expect(editorFocused(tester), isFalse, reason: 'the panel takes the keyboard\'s place');
      await tester.tap(find.text('Heading'));
      await tester.pumpAndSettle();
      bool lit(String label) => tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label)).selected;
      expect([lit('Heading'), lit('Body')], [true, false], reason: 'the chip of the line\'s style lights at once');
      quill(tester).updateSelection(const TextSelection(baseOffset: 5, extentOffset: 9), ChangeSource.local);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bold'));
      await tester.pumpAndSettle();
      expect(markdownOf(tester), '# Shop\n## **Eggs** and milk');
      expect(editorFocused(tester), isFalse, reason: 'a style tap leaves the keyboard down');
      expect(find.byType(FormatSheet), findsOneWidget);
      expect(find.byTooltip('Done'), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(FormatSheet), findsNothing);
      expect(find.byType(FloatingToolBar), findsOneWidget);
      expect(editorFocused(tester), isTrue);
    });

    testWidgets('the format panel is the keyboard\'s full height, not a height from while the keyboard slides down', (tester) async {
      addTearDown(tester.view.resetViewInsets);
      addTearDown(tester.view.resetPhysicalSize);
      tester.view.physicalSize = const Size(390, 844) * tester.view.devicePixelRatio;
      relay.entries = [Entry(id: 'n1', text: 'Shop\nEggs', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      final ratio = tester.view.devicePixelRatio;
      tester.view.viewInsets = FakeViewPadding(bottom: 336 * ratio);
      await tester.pump();
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding(bottom: 150 * ratio);
      await tester.pump();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      final panel = find.descendant(of: find.byType(FormatSheet), matching: find.byType(SizedBox)).first;
      expect(tester.getSize(panel).height, 336);
    });

    testWidgets('Done on the format panel closes it and sends the change', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop\nEggs', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 7), ChangeSource.local);
      await tester.tap(find.byTooltip('Text styles'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Bulleted list'));
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty, reason: 'a style tap while editing waits like typing');
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(FormatSheet), findsNothing);
      expect(find.byType(ReadingBar), findsOneWidget);
      expect(relay.calls, ['edit # Shop\n* Eggs']);
    });

    testWidgets('Return on an empty list line ends the list', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop\n* Eggs', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 9), ChangeSource.local);
      await type(tester, '\n');
      expect(markdownOf(tester), '# Shop\n* Eggs\n* ');
      await type(tester, '\n');
      expect(markdownOf(tester), '# Shop\n* Eggs\n');
    });

    testWidgets('a checklist circle ticks with one tap while reading and is kept at once', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop\n- [ ] Eggs', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.circle));
      await tester.pumpAndSettle();
      expect(find.byIcon(CupertinoIcons.checkmark_circle_fill), findsOneWidget);
      expect(relay.calls, ['edit # Shop\n- [x] Eggs']);
    });

    testWidgets('Checklist while reading adds an item at the end and brings the keyboard up', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Checklist'));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isTrue);
      await type(tester, 'Eggs');
      expect(markdownOf(tester), '# Shop\n- [ ] Eggs');
    });

    testWidgets('Share gives the plain words, and the ⋯ menu copies them and plays a voice note', (tester) async {
      final shared = <String>[];
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      relay.entries = [Entry(id: 'n1', text: 'Shop\n- [ ] **Eggs**', at: now, voice: true, recording: 'voice/a.wav')];
      await tester.pumpWidget(RelayApp(relay: relay, sharer: (text) async => shared.add(text)));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      expect(shared, ['Shop\nEggs']);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, ['Shop\nEggs']);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Play'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['play voice/a.wav']);
    });

    testWidgets('⋯ → Delete, last in the menu, closes the page and deletes the note, with Undo on the list', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Buy milk'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final items = tester.widgetList<MenuItemButton>(find.byType(MenuItemButton)).toList();
      expect((items.last.child! as Text).data, 'Delete');
      await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsNothing);
      expect(relay.calls, ['delete n1']);
      expect([find.text('Buy milk'), find.text('Call Sam'), find.text('Note deleted'), find.text('Undo')],
        [findsNothing, findsOneWidget, findsOneWidget, findsOneWidget]);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['delete n1', 'undo n1']);
      expect(find.text('Buy milk'), findsOneWidget);
    });

    testWidgets('⋯ → Delete on a new note not kept yet keeps nothing and deletes nothing', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Delete'));
      await tester.pumpAndSettle();
      expect([relay.calls, find.byType(NoteEditor).evaluate(), find.text('Note deleted').evaluate()], [isEmpty, isEmpty, isEmpty]);
    });

    testWidgets('on a 375-point phone the ⋯ menu lies on the screen, its right edge in line with the button', (tester) async {
      tester.view
        ..physicalSize = const Size(375, 812)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      relay.entries = [Entry(id: 'n1', text: 'Onfido Verification', at: now, voice: true, recording: 'voice/a.wav')];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Onfido Verification'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      // The pill's card shape is the button the person sees.
      final button = tester.getRect(find.ancestor(of: find.byTooltip('More'), matching: find.byType(ButtonPill)));
      for (final item in ['Copy', 'Play']) {
        final row = tester.getRect(find.widgetWithText(MenuItemButton, item));
        expect(row.left, greaterThanOrEqualTo(12), reason: item);
        expect(row.right, lessThanOrEqualTo(375 - 12), reason: item);
        expect((row.right - button.right).abs(), lessThanOrEqualTo(1), reason: item);
        expect(row.top, greaterThan(button.bottom), reason: item);
      }
      // Round corners on the card color.
      final panel = tester.widgetList<Material>(find.ancestor(of: find.widgetWithText(MenuItemButton, 'Copy'), matching: find.byType(Material)))
        .firstWhere((material) => material.shape is RoundedRectangleBorder &&
          (material.shape! as RoundedRectangleBorder).borderRadius == const BorderRadius.all(Radius.circular(14)));
      expect(panel.color, BrandColors.light.card);
    });

    testWidgets('a web address shows as a link; a tap while reading opens it, and the note stays as it was', (tester) async {
      final opened = <Uri>[];
      const text = 'Onfido Verification\nhttps://id.onfido.com/XX6L46TU\nOr www.example.com.\nHello friend';
      relay.entries = [Entry(id: 'n1', text: text, at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Onfido Verification'));
      await tester.pumpAndSettle();
      final document = quill(tester).document;
      final words = document.toPlainText();
      String? linkOn(String part) => linkAt(document, words.indexOf(part) + 2);
      expect([linkOn('id.onfido'), linkOn('example'), linkOn('Hello'), linkOn('Or ')],
        ['https://id.onfido.com/XX6L46TU', 'www.example.com', null, null]);
      // The stop after an address is not part of the link.
      expect(linkAt(document, words.indexOf('.com.') + 4), isNull);
      // The link draws in the accent text color, underlined.
      final link = noteStyles(tester.element(find.byType(QuillEditor))).link!;
      expect([link.color, link.decoration], [BrandColors.light.accentText, TextDecoration.underline]);
      // A tap on the link while reading opens it, and the keyboard stays down.
      final line = find.text('https://id.onfido.com/XX6L46TU', findRichText: true);
      final at = tester.getTopLeft(line) + Offset(30, tester.getSize(line).height / 2);
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://id.onfido.com/XX6L46TU')]);
      expect(editorFocused(tester), isFalse);
      // While editing, the same tap places the cursor and opens nothing.
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(tester.getTopLeft(find.text('Hello friend', findRichText: true)) + const Offset(10, 8));
      await tester.pump();
      expect(editorFocused(tester), isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(at);
      await tester.pumpAndSettle();
      expect(opened, hasLength(1));
      expect(editorFocused(tester), isTrue);
      final address = words.indexOf('https://id.onfido');
      expect(quill(tester).selection.baseOffset, inInclusiveRange(address, address + 'https://id.onfido.com/XX6L46TU'.length));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty, reason: 'an untouched note is never written back');
    });

    testWidgets('a link mark never reaches the words: a changed note keeps the plain address', (tester) async {
      const text = 'Links\nSee https://example.com/a_b';
      final marked = withLinks(markdownToDelta(text, title: true));
      expect(marked.toList().where((op) => op.attributes?['link'] != null).map((op) => op.data), ['https://example.com/a_b']);
      expect(deltaToMarkdown(marked), '# Links\nSee https://example.com/a_b');
      relay.entries = [Entry(id: 'n1', text: text, at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Links'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Checklist'));
      await tester.pumpAndSettle();
      await type(tester, 'Eggs');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Links\nSee https://example.com/a_b\n- [ ] Eggs']);
    });

    testWidgets('an address typed in this visit becomes a link once editing ends, and the words stay plain', (tester) async {
      final opened = <Uri>[];
      relay.entries = [Entry(id: 'n1', text: 'Trip\nTickets', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tickets', findRichText: true));
      await tester.pump();
      final end = quill(tester).document.length - 1;
      quill(tester).updateSelection(TextSelection.collapsed(offset: end), ChangeSource.local);
      // One letter at a time, as the keyboard types. The editor links an `https://` address as it is typed, but not
      // a `www.` one.
      const typed = ' https://example.com and www.example.com.';
      for (final letter in typed.split('')) {
        await type(tester, letter);
      }
      final www = end + typed.indexOf('www.');
      expect(linkAt(quill(tester).document, www + 5), isNull, reason: 'no www link while typing');
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isFalse);
      expect(linkAt(quill(tester).document, www + 15), isNull, reason: 'the stop is not part of the link');
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(onLetter(tester, www + 5, 0.5));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://www.example.com')]);
      expect(editorFocused(tester), isFalse);
      await tester.tapAt(onLetter(tester, end + 10, 0.5));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://www.example.com'), Uri.parse('https://example.com')]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Trip\nTickets https://example.com and www.example.com.'], reason: 'the stored words keep no link mark');
    });

    testWidgets('a stop typed after an address is not part of its link, and the tap opens the address', (tester) async {
      final opened = <Uri>[];
      relay.entries = [Entry(id: 'n1', text: 'Trip\nTickets', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tickets', findRichText: true));
      await tester.pump();
      final end = quill(tester).document.length - 1;
      quill(tester).updateSelection(TextSelection.collapsed(offset: end), ChangeSource.local);
      const typed = ' See https://a.com. Then';
      for (final letter in typed.split('')) {
        await type(tester, letter);
      }
      // The mark the editor's own space rule leaves when it takes the stop into the link.
      final stop = end + typed.indexOf('. Then');
      final start = end + typed.indexOf('https://');
      quill(tester).formatText(start, stop + 1 - start, const LinkAttribute('https://a.com.'));
      await tester.pump();
      expect(linkAt(quill(tester).document, stop), 'https://a.com.');
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect([linkAt(quill(tester).document, stop - 1), linkAt(quill(tester).document, stop)], ['https://a.com', null]);
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(onLetter(tester, stop - 2, 0.5));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://a.com')]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Trip\nTickets See https://a.com. Then']);
    });

    testWidgets('an edited link keeps no old mark: a removed https:// or a space typed inside', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Links\nGo https://example.com now\nSee https://example.com/path', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (_) async => true));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Links'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(find.text('Links', findRichText: true)) + const Offset(10, 8));
      await tester.pump();
      expect(editorFocused(tester), isTrue);
      final controller = quill(tester);
      final first = controller.document.toPlainText().indexOf('https://');
      controller.replaceText(first, 'https://'.length, '', TextSelection.collapsed(offset: first));
      await tester.pump();
      final path = controller.document.toPlainText().indexOf('/path');
      controller.replaceText(path, 0, ' ', TextSelection.collapsed(offset: path + 1));
      await tester.pump();
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      final document = quill(tester).document;
      final words = document.toPlainText();
      expect(words, 'Links\nGo example.com now\nSee https://example.com /path\n');
      String? linkOn(String part) => linkAt(document, words.indexOf(part) + 1);
      expect([linkOn('example.com now'), linkOn('https://example.com /'), linkOn('/path')], [null, 'https://example.com', null]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['edit # Links\nGo example.com now\nSee https://example.com /path']);
    });

    testWidgets('a tap on the right half of a link\'s last letter opens it; one on the space before it does not', (tester) async {
      final opened = <Uri>[];
      relay.entries = [Entry(id: 'n1', text: 'Links\nGo https://example.com now', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Links'));
      await tester.pumpAndSettle();
      final words = quill(tester).document.toPlainText();
      final start = words.indexOf('https://');
      final last = start + 'https://example.com'.length - 1;
      expect(linkAtPosition(quill(tester).document, TextPosition(offset: last + 1, affinity: TextAffinity.upstream)),
        'https://example.com');
      expect(linkAtPosition(quill(tester).document, TextPosition(offset: start, affinity: TextAffinity.upstream)), isNull);
      await tester.tapAt(onLetter(tester, last, 0.8));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://example.com')]);
      expect(editorFocused(tester), isFalse);
      await tester.pump(const Duration(seconds: 1));
      await tester.tapAt(onLetter(tester, start - 1, 0.8));
      await tester.pumpAndSettle();
      expect(opened, hasLength(1), reason: 'the space before a link places the cursor');
      expect(editorFocused(tester), isTrue);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('Waiting to send is a button that sends now, and says Sending… while it goes', (tester) async {
      relay
        ..connected = true
        ..settings = const Settings(sending: true)
        ..entries = [Entry(id: 'n1', text: 'Shop', at: now, waiting: true), Entry(id: 'n2', text: 'Gone', at: now, sent: true)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Waiting to send · Send now'));
      await tester.pump();
      expect(relay.calls, ['sync']);
      relay
        ..status = SyncStatus.syncing
        ..changed();
      await tester.pump();
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Sending…')).onPressed, isNull);
      relay
        ..status = SyncStatus.synced
        ..changed();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gone'));
      await tester.pumpAndSettle();
      expect([find.text('Sent'), find.byType(TextButton).evaluate().where((element) =>
        (element.widget as TextButton).child is Text && ((element.widget as TextButton).child! as Text).data!.contains('Send now'))],
        [findsOneWidget, isEmpty]);
    });
  });

  testWidgets('turns settings on and says why one could not be', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, pinNotes: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    await tester.tap(find.text('Pin notes to where I am'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openFolder(tester, 'Location');
    await tester.tap(find.text('Location history'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    relay.problem = 'Relay Everything may not read your health data.';
    await openFolder(tester, 'Health');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Health'));
    await tester.pump();
    expect(find.text('Relay Everything may not read your health data.'), findsOneWidget);
    expect(relay.calls, ['pin false', 'history true', 'health true']);
  });

  group('photos', () {
    const denied = "Photo access is off. Turn it on in the phone's Settings.";

    final photosSwitch = find.widgetWithText(SwitchListTile, 'Photos');

    // Opens the Photos folder from Home, under On this phone.
    Future<void> openPhotos(WidgetTester tester) => openFolder(tester, 'Photos');

    testWidgets('Home shows a Photos row that says Off or On, and its page says Photos works with sending on', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));
      expect(find.widgetWithText(ListTile, 'Photos'), findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Photos'), matching: find.text('Off')), findsOneWidget);
      await openPhotos(tester);
      expect(find.text('Photos works with sending on. Nothing leaves this phone until you turn it on.'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      relay
        ..connected = true
        ..server = 'https://relay.example.com'
        ..settings = const Settings(sending: true, photos: true)
        ..changed();
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Photos'), matching: find.text('On · Wi-Fi only')), findsOneWidget);
      expect(relay.calls, isEmpty);
    });

    testWidgets('works only while sending is on, and mobile data only while photos is on', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openPhotos(tester);
      expect(find.text('Sends new photos, with when and where you took them, so your AI can see them.'), findsOneWidget);
      expect(find.text('Off: photos wait for Wi-Fi.'), findsOneWidget);
      expect([switchOf(tester, 'Photos').onChanged, switchOf(tester, 'Send photos on mobile data').onChanged], [isNull, isNull]);
      await tester.tap(photosSwitch);
      await tester.pump();
      relay
        ..connected = true
        ..server = 'https://relay.example.com'
        ..settings = const Settings(sending: true)
        ..changed();
      await tester.pump();
      expect([switchOf(tester, 'Photos').onChanged, switchOf(tester, 'Send photos on mobile data').onChanged], [isNotNull, isNull]);
      relay
        ..settings = const Settings(sending: true, photos: true)
        ..changed();
      await tester.pump();
      expect([switchOf(tester, 'Photos').value, switchOf(tester, 'Send photos on mobile data').onChanged], [isTrue, isNotNull]);
      await tester.tap(find.text('Send photos on mobile data'));
      await tester.pump();
      expect(relay.calls, ['mobile data true']);
    });

    testWidgets('refused photo access keeps photos off and says where to turn it on', (tester) async {
      relay
        ..connected = true
        ..server = 'https://relay.example.com'
        ..settings = const Settings(sending: true)
        ..problem = denied;
      await tester.pumpWidget(RelayApp(relay: relay));
      await openPhotos(tester);
      await tester.tap(photosSwitch);
      await tester.pump();
      expect(find.text(denied), findsOneWidget);
      expect([relay.calls, switchOf(tester, 'Photos').value], [['photos true'], isFalse]);
      expect(find.text('Stop sending photos?'), findsNothing);
    });

    testWidgets('turning off says where the photos sent stay, and opens the page or stops', (tester) async {
      final opened = <Uri>[];
      var opens = true;
      relay
        ..connected = true
        ..server = 'https://relay.example.com'
        ..settings = const Settings(sending: true, photos: true);
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return opens;
      }));
      await openPhotos(tester);
      await tester.tap(photosSwitch);
      await tester.pumpAndSettle();
      expect(find.text('Stop sending photos?'), findsOneWidget);
      expect(find.text('Photos already sent stay on your Relay Everything server. Delete them on your page.'), findsOneWidget);
      await tester.tap(find.text('Open my page'));
      await tester.pumpAndSettle();
      expect([opened, relay.calls], [[Uri.parse('https://relay.example.com/apps/relay/')], isEmpty]);
      expect(find.text('Stop sending photos?'), findsNothing);
      await tester.tap(photosSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop sending photos'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['photos false']);
      // The browser does not open: the app says so, and photos stay on.
      opens = false;
      await tester.tap(photosSwitch);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open my page'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The browser did not open. Try again.'), findsOneWidget);
      expect([opened, relay.calls], [hasLength(2), ['photos false']]);
    });

    testWidgets('sending to your own webhook shows both photo switches, says photos go there, and turns off with no page dialog', (tester) async {
      relay
        ..webhookAddress = 'https://db.example.com/relay'
        ..settings = const Settings(sending: true, place: SendPlace.webhook, photos: true);
      await tester.pumpWidget(RelayApp(relay: relay));
      await openPhotos(tester);
      expect([photosSwitch, find.text('Send photos on mobile data'),
        find.text('Sends new photos, with when and where you took them, to your webhook.')], everyElement(findsOneWidget));
      await tester.tap(photosSwitch);
      await tester.pumpAndSettle();
      expect([find.text('Stop sending photos?'), find.text('Open my page')], everyElement(findsNothing));
      expect(relay.calls, ['photos false']);
    });
  });

  testWidgets('on iPhone, location history offers Save battery or Every 100 m; Android offers no choice', (tester) async {
    relay
      ..connected = true
      ..locationModes = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Location');
    expect(find.text('Save battery'), findsNothing);
    relay.settings = const Settings(sending: true, history: true);
    relay.changed();
    await tester.pumpAndSettle();
    expect(find.text('How often'), findsOneWidget);
    RadioGroup<LocationMode> group() => tester.widget(find.byType(RadioGroup<LocationMode>));
    expect(group().groupValue, LocationMode.battery);
    await tester.tap(find.text('Every 100 m'));
    await tester.pumpAndSettle();
    expect([relay.calls, group().groupValue], [['mode move'], LocationMode.move]);
    relay.locationModes = false;
    relay.changed();
    await tester.pumpAndSettle();
    expect(find.text('Every 100 m'), findsNothing);
  });

  testWidgets('says when health and places last went, and how many wait', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true, health: true, history: true)
      ..healthSent = SendState(at: DateTime(now.year, now.month, now.day, 14, 5), waiting: 3);
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Sent 14:05 · 3 waiting'), findsOneWidget);
    await openFolder(tester, 'Health');
    expect(find.text('Sent 14:05 · 3 readings waiting'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await openFolder(tester, 'Location');
    expect(find.text('Not sent yet · none waiting'), findsOneWidget);
    final today = DateTime(2026, 11, 7, 18);
    expect(sentLine(SendState(at: DateTime(2026, 11, 6, 9, 30), waiting: 1), 'point', today), 'Sent 6/11 09:30 · 1 point waiting');
    expect(sentLine(SendState(at: DateTime(2026, 11, 7, 9, 3)), 'point', today), 'Sent 09:03 · none waiting');
  });

  testWidgets('lists the phone\'s calendars only while the calendar is on, each with its own switch', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..calendarSent = SendState(at: DateTime(now.year, now.month, now.day, 10, 42), waiting: 2);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Calendar');
    expect(find.text('US Holidays'), findsNothing);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Calendar'));
    await tester.pump();
    expect(relay.calls, ['calendar true']);
    relay
      ..settings = const Settings(sending: true, calendar: true)
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('Sent 10:42 · 2 events waiting'), findsOneWidget);
    expect(find.text('sam@example.com'), findsOneWidget);
    expect(switchOf(tester, 'US Holidays').value, isTrue);
    await tester.tap(find.text('US Holidays'));
    await tester.pumpAndSettle();
    expect([relay.calls.last, switchOf(tester, 'US Holidays').value, switchOf(tester, 'Work').value],
      ['calendar holidays false', false, true]);
    relay
      ..settings = const Settings()
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('US Holidays'), findsNothing);
    expect(switchOf(tester, 'Calendar').onChanged, isNull);
  });

  testWidgets('changes the server, and disconnects after asking', (tester) async {
    tallScreen(tester);
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Sending');
    await tester.tap(find.text('https://relay.example.com'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('https://relay.example.com'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://preview.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect this phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect this phone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disconnect'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['server https://preview.example.com', 'disconnect']);
    expect(find.text('Disconnect this phone'), findsNothing);
    expect(switchOf(tester, 'Send my notes').value, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Off: nothing leaves this phone'), findsOneWidget);
  });

  testWidgets('sets up a webhook with no key: refuses a bad address, copies the secret, tests it, and saves', (tester) async {
    final copied = <String>[];
    relay.earlier = 2;
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async {
        final place = await Navigator.of(context).push(MaterialPageRoute<SendPlace>(
          builder: (_) => ConnectScreen(relay: relay, copy: (text) async => copied.add(text))));
        relay.calls.add('closed ${place?.name}');
      },
      child: const Text('Open'))))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to connect'), findsOneWidget);
    await tester.tap(find.text('My own webhook'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to connect'), findsNothing);
    final secret = relay.newWebhookSecret();
    expect(find.text(secret), findsOneWidget);
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect([copied, find.text('Secret copied.').evaluate().length], [[secret], 1]);
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
    await tester.tap(find.text('Send a test'));
    await tester.pumpAndSettle();
    expect(find.text('Your receiver answered 204. It works.'), findsOneWidget);
    relay.problem = 'The address must start with https://.';
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The address must start with https://.'), findsOneWidget);
    relay.problem = null;
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['test https://db.example.com/relay', 'webhook https://db.example.com/relay $secret',
      'webhook https://db.example.com/relay $secret', 'closed webhook']);
  });

  testWidgets('in Sending, My own webhook says sync is off there, and opens Webhooks on the Relay Everything page', (tester) async {
    final opened = <Uri>[];
    tallScreen(tester);
    relay
      ..settings = const Settings(sending: true, place: SendPlace.webhook)
      ..webhookAddress = 'https://db.example.com/relay';
    await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
      opened.add(address);
      return true;
    }));
    await openFolder(tester, 'Sending');
    await tester.scrollUntilVisible(find.text('Notes from elsewhere'), 100);
    expect(find.textContaining('Sync is off while the phone sends to your own webhook.'), findsOneWidget);
    await tester.tap(find.text('Notes from elsewhere'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://app.relayeverything.com/apps/relay/#webhooks')]);
  });

  testWidgets('a note from elsewhere names where it came from, offers no paperclip, and lists files to download',
      (tester) async {
    relay.entries = [Entry(id: 'srv:s1', text: 'Flight moved to 9:40', at: now, from: 'Email', files: const [
      EntryFile(id: 'f1', name: 'ticket.pdf', type: 'application/pdf', size: 3, path: ''),
      EntryFile(id: 'f2', name: 'boarding.png', type: 'image/png', size: 2048, path: ''),
    ])];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(find.textContaining('· Email'), findsOneWidget);
    await tester.tap(find.text('Flight moved to 9:40'));
    await tester.pumpAndSettle();
    expect([find.textContaining('From Email'), find.text('3 B · Download'), find.text('2 KB · Download')],
      [findsOneWidget, findsOneWidget, findsOneWidget]);
    expect(tester.widget<IconButton>(find.ancestor(of: find.byTooltip('Attach'), matching: find.byType(IconButton))).onPressed,
      isNull);
    await tester.tap(find.text('ticket.pdf'));
    expect(relay.calls, ['open ticket.pdf']);
  });

  testWidgets('in Sending, picks My own webhook, asks about earlier notes, and shows where it sends and its last problem',
    (tester) async {
    relay.earlier = 2;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Sending');
    await tester.tap(find.text('Send my notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My own webhook'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('They were only on this phone. New notes go to your webhook from now on.'), findsOneWidget);
    await tester.tap(find.text('Send them'));
    await tester.pumpAndSettle();
    expect(relay.calls.last, 'start true webhook');
    expect(find.textContaining('To your webhook: db.example.com. Nothing goes to Relay Everything'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('https://db.example.com/relay'), 100);
    expect(find.text('Where the phone sends'), findsOneWidget);
    expect([find.text('Server').evaluate(), find.text('Disconnect this phone').evaluate()], [isEmpty, isEmpty]);
    relay.testAnswer = 'Your receiver answered 401. Check that it has this secret.';
    await tester.ensureVisible(find.widgetWithText(TextButton, 'Send a test'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Send a test'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Your receiver answered 401. Check that it has this secret.'), findsOneWidget);
    final at = DateTime.now();
    relay
      ..webhookProblem = WebhookProblem(at: at, status: 503)
      ..changed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text(problemLine(relay.webhookProblem!, at)), 100);
    expect(problemLine(WebhookProblem(at: DateTime(2026, 11, 4, 9, 5), status: null), DateTime(2026, 11, 6)),
      'No answer from your receiver at 4/11 09:05. Notes wait on this phone until it answers.');
    expect(problemLine(WebhookProblem(at: DateTime(2026, 11, 6, 14, 5), status: 413, file: 'scan.pdf'), DateTime(2026, 11, 6)),
      'scan.pdf was too large for your receiver (14:05), so it was not sent.');
  });

  testWidgets('Settings shows only the Appearance, Notes and Voice notes groups, with no lines, and the version', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    final groups = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(SliverList));
    for (final heading in ['Appearance', 'Notes', 'Voice notes']) {
      expect(find.descendant(of: groups, matching: find.text(heading)), findsOneWidget, reason: heading);
    }
    expect(tester.getTopLeft(find.text('Appearance')).dy, lessThan(tester.getTopLeft(find.text('Notes').last).dy));
    for (final segment in ['System', 'Light', 'Dark']) {
      expect(find.text(segment), findsOneWidget, reason: segment);
    }
    expect(find.text('Relay Everything 1.4.0 (91)'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Relay Everything 1.4.0 (91)')).dy, greaterThan(tester.getTopLeft(find.text('Speech model')).dy));
    for (final gone in ['Sending', 'Send my notes', 'Health', 'Calendar', 'Location history', 'Send photos on mobile data']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Divider)), findsNothing);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Off: nothing leaves this phone'), findsOneWidget);
  });

  testWidgets('with sending off, a data folder says it needs sending, and Turn on sending asks where to send', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));
    for (final (folder, what) in [('Location', 'Location history'), ('Health', 'Health'), ('Calendar', 'Calendar'),
      ('Photos', 'Photos')]) {
      await openFolder(tester, folder);
      expect(switchOf(tester, what).onChanged, isNull, reason: what);
      expect(find.text('$what works with sending on. Nothing leaves this phone until you turn it on.'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    await openFolder(tester, 'Health');
    await tester.tap(find.widgetWithText(FilledButton, 'Turn on sending'));
    await tester.pumpAndSettle();
    expect(find.text('Where should the phone send?'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
  });

  testWidgets('Home counts each notes folder, and Voice notes lists only voice notes, with Home to go back', (tester) async {
    const photo = EntryFile(name: 'receipt.jpg', type: 'image/jpeg', size: 1258291, path: '/nowhere/receipt.jpg');
    relay.entries = [
      for (final words in ['Buy milk', 'Gift ideas', 'Paint the hall']) Entry(text: words, at: now),
      for (final words in ['Call the fab', 'Ask Sam']) Entry(text: words, at: now, voice: true),
      Entry(text: 'Receipt for the lamp', at: now, files: const [photo]),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect([countOn('Notes', 6), countOn('Voice notes', 2), countOn('Shares', 1)], everyElement(findsOneWidget));
    await openFolder(tester, 'Voice notes');
    expect(find.byType(TimelineScreen), findsOneWidget);
    expect([find.text('Call the fab'), find.text('Ask Sam')], everyElement(findsOneWidget));
    expect([find.text('Buy milk'), find.text('Receipt for the lamp')], everyElement(findsNothing));
    expect(find.text('2 notes ·'), findsOneWidget);
    await tester.tap(find.text('Call the fab'));
    await tester.pumpAndSettle();
    // A note opened from a folder goes back to that folder.
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Voice notes')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Home')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(countOn('Notes', 6), findsOneWidget);
  });

  testWidgets('search on Home finds notes in every folder, on the phone only; Cancel shows the folders again', (tester) async {
    relay.entries = [
      Entry(text: 'Call the dentist', at: now),
      Entry(text: 'Dentist moved to Thursday', at: now, voice: true),
      Entry(text: 'Gift ideas', at: now),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Gift ideas'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'dentist');
    await tester.pump();
    expect([find.text('Call the dentist'), find.text('Dentist moved to Thursday')], everyElement(findsOneWidget));
    expect([find.text('Gift ideas'), find.widgetWithText(ListTile, 'Voice notes')], everyElement(findsNothing));
    await tester.tap(find.text('Dentist moved to Thursday'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Home')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect([find.widgetWithText(ListTile, 'Voice notes'), find.text('Call the dentist')], [findsOneWidget, findsNothing]);
    // In a folder, search finds that folder's notes only.
    await openFolder(tester, 'Voice notes');
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'dentist');
    await tester.pump();
    expect([find.text('Dentist moved to Thursday'), find.text('Call the dentist')], [findsOneWidget, findsNothing]);
    expect(relay.calls, isEmpty);
  });

  testWidgets('a tap on On this phone or Connections folds it, and the phone keeps it folded', (tester) async {
    tallScreen(tester);
    relay.settings = const Settings(sending: true, place: SendPlace.webhook);
    await tester.pumpWidget(RelayApp(relay: relay));
    // A section name folds with no grey highlight: no ink sits behind it.
    for (final name in ['On this phone', 'Connections']) {
      expect(find.ancestor(of: find.text(name), matching: find.byType(InkWell)), findsNothing);
    }
    await tester.tap(find.text('On this phone'));
    await tester.pumpAndSettle();
    expect([find.text('Location'), find.text('Health')], everyElement(findsNothing));
    expect(relay.calls, ['fold On this phone true']);
    await tester.tap(find.text('Connections'));
    await tester.pumpAndSettle();
    expect([find.text('Sending'), find.text('AI apps')], everyElement(findsNothing));
    await tester.tap(find.text('On this phone'));
    await tester.pumpAndSettle();
    expect(find.text('Location'), findsOneWidget);
    expect(relay.folded, {'Connections'});
    // A new start reads what the phone kept.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RelayApp(relay: relay));
    expect([find.text('Location'), find.text('AI apps')], [findsOneWidget, findsNothing]);
  });

  testWidgets('AI apps and Webhooks say Sign in to see until the phone sends to a server, then name what is connected',
      (tester) async {
    tallScreen(tester);
    final opened = <Uri>[];
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null, opener: (address) async {
      opened.add(address);
      return true;
    }));
    expect(relay.refreshes, 1);
    expect(find.text('Sign in to see'), findsNWidgets(2));
    await openFolder(tester, 'AI apps');
    expect(find.text('Where should the phone send?'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    // On the person's own webhook, the phone knows nothing of the server.
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, place: SendPlace.webhook)
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('Sign in to see'), findsNWidgets(2));
    relay
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('See them on your page'), findsNWidgets(2));
    relay
      ..connections = const Connections(aiApps: ['Claude'], webhooks: ['Home server', 'Notion sync'])
      ..changed();
    await tester.pumpAndSettle();
    expect([find.text('Claude'), find.text('Home server, Notion sync'), countOn('Webhooks', 2), countOn('AI apps', 1)],
      everyElement(findsOneWidget));
    await openFolder(tester, 'Webhooks');
    await openFolder(tester, 'AI apps');
    expect(opened, [Uri.parse('https://relay.example.com/apps/relay/#webhooks'), Uri.parse('https://relay.example.com/apps/relay/#ai-apps')]);
    relay
      ..connections = const Connections()
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('None yet'), findsNWidgets(2));
    expect(relay.calls, isEmpty);
  });

  test('each Home row says Off, or what the phone knows', () {
    final today = DateTime(now.year, now.month, now.day, 18);
    final fake = FakeRelay();
    expect([locationLine(fake, today), healthLine(fake, today), calendarLine(fake, today), photosLine(fake), sendingLine(fake)],
      ['Off', 'Off', 'Off', 'Off', 'Off: nothing leaves this phone']);
    fake
      ..locationModes = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, history: true, health: true, calendar: true, calendarsOff: {'holidays'})
      ..pointsSent = SendState(at: DateTime(now.year, now.month, now.day, 14, 5))
      ..healthSent = SendState(at: DateTime(now.year, now.month, now.day, 14, 2), waiting: 3)
      ..calendarSent = SendState(at: DateTime(now.year, now.month, now.day, 13, 40));
    expect([locationLine(fake, today), healthLine(fake, today), calendarLine(fake, today), sendingLine(fake)],
      ['Save battery · Sent 14:05', 'Sent 14:02 · 3 waiting', '1 calendar · Sent 13:40', 'To Relay Everything · relay.example.com']);
    fake
      ..locationModes = false
      ..pointsSent = const SendState(waiting: 2)
      ..settings = const Settings(sending: true, place: SendPlace.webhook, history: true, calendar: true)
      ..webhookAddress = 'https://db.example.com/relay';
    expect([locationLine(fake, today), calendarLine(fake, today), sendingLine(fake)],
      ['Not sent yet · 2 waiting', '2 calendars · Sent 13:40', 'To your webhook · db.example.com']);
    fake.settings = const Settings(sending: true, history: true, mode: LocationMode.move);
    fake.locationModes = true;
    expect(locationLine(fake, today), 'Every 100 m · Not sent yet · 2 waiting');
    fake.settings = const Settings(sending: true, photos: true);
    expect(photosLine(fake), 'On · Wi-Fi only');
    fake.settings = const Settings(sending: true, photos: true, photosOnMobileData: true);
    expect(photosLine(fake), 'On · Wi-Fi and mobile data');
  });

  group('voice notes', () {
    testWidgets('hold New note: at 0.5 s it turns into the mic and listens, letting go keeps it, a tap anywhere saves',
        (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      final gesture = await tester.startGesture(tester.getCenter(newNote));
      await tester.pump(const Duration(milliseconds: 300));
      expect(relay.calls, isEmpty);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(relay.calls, ['voice start']);
      expect(find.descendant(of: newNote, matching: find.byIcon(CupertinoIcons.mic_fill)), findsOneWidget);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Tap anywhere to save.'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['voice start']);
      expect(find.text('Listening'), findsOneWidget);
      await tapAnywhere(tester);
      expect(relay.calls, ['voice start', 'voice end']);
      expect([find.text('Listening'), find.byType(NoteEditor)], [findsNothing, findsNothing]);
    });

    testWidgets('a voice note and Listening wear the spark color; a typed note wears accent soft', (tester) async {
      relay.entries = [Entry(text: 'Spoken', at: now, voice: true), Entry(text: 'Written', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      expect(tagColors(tester, 'Voice'), (BrandColors.light.spark, BrandColors.light.onSpark));
      expect(tagColors(tester, 'Typed'), (BrandColors.light.accentSoft, BrandColors.light.accentText));
      await holdNewNote(tester);
      expect(tagColors(tester, 'Listening'), (BrandColors.light.spark, BrandColors.light.onSpark));
      await tapAnywhere(tester);
    });

    testWidgets('a press under 0.5 s opens the page to write and records nothing', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      final gesture = await tester.startGesture(tester.getCenter(newNote));
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      expect(relay.calls, isEmpty);
    });

    testWidgets('Cancel keeps nothing', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(relay.calls, ['voice start', 'voice cancel']);
      expect(find.text('Listening'), findsNothing);
    });

    testWidgets('a voice note the phone could not keep says so, and the card closes', (tester) async {
      relay.endProblem = 'The voice note did not save.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tapAnywhere(tester);
      expect([find.text('Listening'), find.text('The voice note did not save.')], [findsNothing, findsOneWidget]);
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('a recording too short to keep says so', (tester) async {
      relay.endProblem = 'Too short to keep. Nothing was saved.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tapAnywhere(tester);
      expect(find.text('Too short to keep. Nothing was saved.'), findsOneWidget);
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('a voice note shows Writing the words, then its words, its length and Play', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      // The bar moves until the words come, so the screen never settles while it shows.
      relay
        ..entries = [Entry(text: '', at: now, voice: true, writing: true, recording: 'voice/a.wav',
          length: const Duration(seconds: 12))]
        ..changed();
      await tester.pump();
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Writing the words…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      relay
        ..entries = [Entry(text: 'Ask the fab if the flex stiffener can be 0.2 mm', at: now, voice: true,
          recording: 'voice/a.wav', length: const Duration(seconds: 12))]
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('Writing the words…'), findsNothing);
      expect(find.text('Ask the fab if the flex stiffener can be 0.2 mm'), findsOneWidget);
      expect(find.textContaining('0:12'), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      await tester.tap(find.text('Ask the fab if the flex stiffener can be 0.2 mm'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      await tester.tap(find.text('Play'));
      expect(relay.calls, ['play voice/a.wav']);
      await tester.pageBack();
      await tester.pumpAndSettle();
      // A typed note has no Play.
      relay
        ..entries = [Entry(text: 'Typed', at: now)]
        ..changed();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Typed').first);
      await tester.pumpAndSettle();
      expect([find.text('Play'), find.text('Voice')], [findsNothing, findsNothing]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      relay.notice('No speech heard. Nothing was saved.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No speech heard. Nothing was saved.'), findsOneWidget);
    });

    testWidgets('a note whose words failed says so in the list; its page says the recording is safe, keeps Play, and Try again writes them again', (tester) async {
      relay.entries = [Entry(text: '', at: now, voice: true, failed: true, recording: 'voice/a.wav',
        length: const Duration(seconds: 3))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Voice notes');
      expect(find.text('The words did not come'), findsOneWidget);
      expect([find.text('Writing the words…'), find.byType(LinearProgressIndicator)], [findsNothing, findsNothing]);
      await tester.tap(find.text('The words did not come'));
      await tester.pumpAndSettle();
      expect(find.text('The words did not come. Your recording is safe.'), findsOneWidget);
      expect([find.text('Writing the words…'), find.byType(LinearProgressIndicator)], [findsNothing, findsNothing]);
      expect(find.text('Play'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(relay.calls, ['words again']);
      relay.notice('The words did not come. Tap Try again on the note.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The words did not come. Tap Try again on the note.'), findsOneWidget);
    });

    testWidgets('with no model, a hold asks first, and Not now gets nothing', (tester) async {
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(find.textContaining('57 MB'), findsOneWidget);
      expect(find.textContaining('Your voice never leaves this phone.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
      expect(find.textContaining('Getting the speech model'), findsNothing);
    });

    testWidgets('with a screen reader, New note writes on a tap and records once on its action; a tap saves', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(RelayApp(relay: relay));
      tester.semantics.tap(find.semantics.byLabel('New note'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      tester.semantics.performAction(find.semantics.byLabel('New note'), SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Record a voice note')));
      await tester.pump();
      await tester.pump();
      expect([relay.calls, find.text('Listening').evaluate().length], [['voice start'], 1]);
      tester.semantics.tap(find.semantics.byLabel('Save the voice note'));
      await tester.pump();
      expect(relay.calls, ['voice start', 'voice end']);
      semantics.dispose();
    });

    testWidgets('with a screen reader and no model, the action asks the first-time question', (tester) async {
      final semantics = tester.ensureSemantics();
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      tester.semantics.performAction(find.semantics.byLabel('New note'), SemanticsAction.customAction,
        args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Record a voice note')));
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
      semantics.dispose();
    });

    testWidgets('Get it shows the progress card, and typed notes still work', (tester) async {
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get it'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'get model']);
      expect(find.text('Getting the speech model… 40%'), findsOneWidget);
      expect(find.text('You can type notes now. Voice notes start when it is done.'), findsOneWidget);
      await holdNewNote(tester);
      expect(find.textContaining('still coming'), findsOneWidget);
      expect(relay.calls, ['ask model', 'get model']);
    });

    testWidgets('a failed download says why and offers Try again', (tester) async {
      relay
        ..speechModel = ModelState.failed
        ..modelProblem = ModelProblem.offline;
      await tester.pumpWidget(RelayApp(relay: relay));
      expect(find.text('The speech model did not finish downloading.'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['get model']);
      relay
        ..speechModel = ModelState.failed
        ..modelProblem = ModelProblem.damaged
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('The speech model came damaged, so the phone deleted it.'), findsOneWidget);
    });

    testWidgets('a refused microphone says where to allow it', (tester) async {
      relay.startProblem = 'Relay Everything may not use the microphone. Allow it in the phone\'s settings.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      expect(find.textContaining('may not use the microphone'), findsOneWidget);
      expect(find.text('Listening'), findsNothing);
    });

    testWidgets('Settings shows the model and its size; Remove returns the button to the first-time question', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openSettings(tester);
      expect(find.text('Voice notes'), findsOneWidget);
      expect(find.text('On this phone, 57 MB. Your voice never leaves it.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['remove model']);
      expect(find.text('Remove'), findsNothing);
      expect(find.textContaining('Not on this phone'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await holdNewNote(tester);
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(relay.calls, ['remove model', 'ask model']);
    });
  });

  group('files', () {
    testWidgets('the paperclip adds photos and files to a new note and to an old one', (tester) async {
      final picks = <bool>[];
      Future<List<NewFile>> picker({required bool photos}) async {
        picks.add(photos);
        return photos
          ? [const NewFile(path: '/picked/a.jpg', name: 'receipt.jpg', size: 1258291)]
          : [const NewFile(path: '/picked/b.pdf', name: 'warranty.pdf', size: 245760)];
      }
      relay.entries = [Entry(id: 'n1', text: 'Desk lamp', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay, picker: picker));
      await openFolder(tester, 'Notes');
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await type(tester, 'Receipt');
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(relay.calls.single, startsWith('note # Receipt + receipt.jpg'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      relay.calls.clear();
      await tester.tap(find.text('Desk lamp'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      // The old note's words are unchanged, so only the file goes with them.
      expect(relay.calls, ['edit Desk lamp + warranty.pdf']);
      expect(picks, [true, false]);
    });

    testWidgets('a row shows its first picture small; its page shows each picture and file, and a tap opens one',
        (tester) async {
      relay.entries = [
        Entry(text: 'Receipt for the desk lamp', at: now, files: const [
          EntryFile(name: 'receipt.jpg', type: 'image/jpeg', size: 1258291, path: '/nowhere/receipt.jpg'),
          EntryFile(name: 'warranty.pdf', type: 'application/pdf', size: 245760, path: '/nowhere/warranty.pdf'),
        ]),
        Entry(text: '', at: now.subtract(const Duration(minutes: 1)),
          files: const [EntryFile(name: 'only.pdf', type: 'application/pdf', size: 512, path: '/nowhere/only.pdf')]),
      ];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Shares');
      expect(find.byTooltip('receipt.jpg'), findsOneWidget);
      // A note of files alone takes its first file's name as its title.
      expect(find.text('only.pdf'), findsOneWidget);
      await tester.tap(find.text('Receipt for the desk lamp'));
      await tester.pumpAndSettle();
      expect([find.text('warranty.pdf'), find.text('240 KB'), find.byTooltip('receipt.jpg')], everyElement(findsOneWidget));
      expect(find.text('No words, only the recording.'), findsNothing);
      await tester.tap(find.text('warranty.pdf'));
      await tester.tap(find.byTooltip('receipt.jpg'));
      expect(relay.calls, ['open warranty.pdf', 'open receipt.jpg']);
    });
  });

  group('start a voice note from Shortcuts', () {
    Future<StreamController<void>> openWithRequest(WidgetTester tester) async {
      final requests = StreamController<void>();
      addTearDown(requests.close);
      await tester.pumpWidget(RelayApp(relay: relay, voiceRequests: requests.stream));
      requests.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return requests;
    }

    testWidgets('records at once in the same listening card; a tap anywhere saves', (tester) async {
      await openWithRequest(tester);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Tap anywhere to save.'), findsOneWidget);
      expect(relay.calls, ['voice start']);
      await tapAnywhere(tester);
      expect(find.text('Listening'), findsNothing);
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('Cancel keeps nothing', (tester) async {
      await openWithRequest(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(find.text('Listening'), findsNothing);
      expect(relay.calls, ['voice start', 'voice cancel']);
    });

    testWidgets('records over a folder page that is open, and the folder shows again after', (tester) async {
      final requests = StreamController<void>();
      addTearDown(requests.close);
      await tester.pumpWidget(RelayApp(relay: relay, voiceRequests: requests.stream));
      await openFolder(tester, 'Health');
      requests.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect([find.text('Listening'), find.byType(HealthPage)], everyElement(findsOneWidget));
      await tapAnywhere(tester);
      expect([relay.calls, find.text('Listening').evaluate()], [['voice start', 'voice end'], isEmpty]);
      expect(find.byType(HealthPage), findsOneWidget);
    });

    testWidgets('with no speech model, it asks to get it first, as a hold on New note does', (tester) async {
      relay.speechModel = ModelState.missing;
      await openWithRequest(tester);
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(find.text('Listening'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
    });
  });
}
