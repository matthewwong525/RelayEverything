import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart' show ValueListenable;
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
import 'package:relay_app/screens/connect_ai.dart' show ConnectAiPage, computerLine;
import 'package:relay_app/screens/email_notes.dart' show EmailNotesPage;
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/screens/folder.dart';
import 'package:relay_app/screens/note_bars.dart';
import 'package:relay_app/screens/note_blocks.dart' show VoicePlayer, WavePainter;
import 'package:relay_app/screens/note_editor.dart';
import 'package:relay_app/screens/round_button.dart' show ButtonPill;
import 'package:relay_app/screens/settings.dart' show SettingsRow, SettingsScreen;
import 'package:relay_app/screens/timeline.dart' show FoldHeader, SyncLine, TimelineScreen, TitleBar;
import 'package:relay_app/screens/transcripts.dart' show CommandBox, TranscriptsPage;
import 'package:relay_app/screens/webhooks.dart' show WebhooksPage;

class FakeRelay extends Relay {
  /// The phone app, or the browser for a test of the web page.
  @override RelayPlatform platform = RelayPlatform.phone;
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

  @override
  Future<String?> setLocationSend(LocationSend send) async {
    calls.add('send ${send.name}');
    settings = settings.copyWith(locationSend: send);
    notifyListeners();
    return problem;
  }

  @override Future<String?> setServer(String server) async { calls.add('server $server'); return problem; }

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
  /// The place the last [earlierNotes] asked about.
  SendPlace? earlierTo;
  @override
  Future<int> earlierNotes({SendPlace? to}) async {
    earlierTo = to;
    return earlier;
  }

  @override
  Future<String?> startSending({required bool sendEarlier, SendPlace? place, SendPlace? privateTo}) async {
    calls.add('start $sendEarlier${place == SendPlace.webhook ? ' webhook' : ''}'
      '${privateTo == null ? '' : ' private ${privateTo.name}'}');
    settings = settings.copyWith(sending: true, place: place, privateTo: privateTo);
    notifyListeners();
    return null;
  }

  @override bool privateWebhookMissing = false;

  @override
  Future<String?> setPrivatePlace(SendPlace place) async {
    calls.add('private ${place.name}');
    if (problem == null) {
      settings = settings.copyWith(privateTo: place);
      privateWebhookMissing = false;
      notifyListeners();
    }
    return problem;
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
  Future<String?> signOutPhone(String id) async {
    calls.add('sign out $id');
    if (connections case final kept? when problem == null) {
      connections = Connections(email: kept.email, aiApps: kept.aiApps, webhooks: kept.webhooks, thisDevice: kept.thisDevice,
        devices: [for (final device in kept.devices) if (device.id != id) device], notesAddress: kept.notesAddress,
        sharedAddress: kept.sharedAddress, addressesKnown: kept.addressesKnown);
      notifyListeners();
    }
    return problem;
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

  /// Pins at once, as the controller does: the note keeps its words and its time.
  @override
  Future<void> pinNote(String id, bool pinned) async {
    calls.add('${pinned ? 'pin' : 'unpin'} $id');
    entries = [for (final entry in entries) entry.id == id ? pinnedCopy(entry, pinned) : entry];
    notifyListeners();
  }

  static String _names(List<NewFile> files) => files.isEmpty ? '' : ' + ${[for (final file in files) file.name].join(', ')}';

  @override Future<void> openFile(EntryFile file) async => calls.add('open ${file.name}');

  @override ModelState speechModel = ModelState.ready;
  @override double modelProgress = 0;
  @override ModelProblem? modelProblem;
  @override int modelBytes = 59721011;
  @override DateTime? listening;
  /// What the recording screen's bars draw while listening: a test adds levels to it.
  final levels = StreamController<double>.broadcast();
  @override Stream<double>? get level => listening == null ? null : levels.stream;
  @override bool holdTipSeen = false;
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
      holdTipSeen = true;
      listening = DateTime.now();
      notifyListeners();
    }
    return startProblem;
  }

  /// How many voice notes a save kept.
  int voiceNotes = 0;

  /// A save with no problem keeps the note, as the app's Relay does: it shows at once, writing its words, at the time
  /// the recording started, to the millisecond the phone keeps.
  @override
  Future<String?> endVoiceNote() async {
    calls.add('voice end');
    final since = listening;
    listening = null;
    if (endProblem == null && since != null) {
      voiceNotes++;
      entries = [Entry(id: 'voice-$voiceNotes', text: '', at: DateTime.fromMillisecondsSinceEpoch(since.millisecondsSinceEpoch),
        voice: true, writing: true, recording: 'voice/$voiceNotes.wav', length: const Duration(seconds: 4)), ...entries];
    }
    notifyListeners();
    return endProblem;
  }

  @override
  Future<void> cancelVoiceNote() async {
    calls.add('voice cancel');
    listening = null;
    notifyListeners();
  }

  /// What plays now, as a phone's player would say it.
  final sound = ValueNotifier<Playback?>(null);
  /// The sound waves [waveOf] gives; none draws a plain line.
  List<double> waves = const [];

  @override ValueListenable<Playback?> get playback => sound;

  @override
  Future<void> play(String recording) async {
    calls.add('play $recording');
    final at = sound.value?.recording == recording ? sound.value!.at : Duration.zero;
    sound.value = Playback(recording: recording, at: at, playing: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    if (sound.value case final now?) sound.value = Playback(recording: now.recording, at: now.at, playing: false);
  }

  @override
  Future<void> seek(Duration at) async {
    calls.add('seek ${at.inMilliseconds}');
    if (sound.value case final now?) sound.value = Playback(recording: now.recording, at: at, playing: now.playing);
  }

  @override Future<List<double>> waveOf(String recording, {int bars = 48}) async => waves;
  @override Future<void> writeWordsAgain() async => calls.add('words again');
}

final now = DateTime.now();

/// [entry], pinned or not.
Entry pinnedCopy(Entry entry, bool pinned) => Entry(id: entry.id, text: entry.text, at: entry.at, sent: entry.sent,
  waiting: entry.waiting, voice: entry.voice, writing: entry.writing, failed: entry.failed, why: entry.why,
  noWords: entry.noWords, recording: entry.recording, length: entry.length, files: entry.files, from: entry.from, pinned: pinned);

/// The round *New note* button: a tap writes, a hold talks.
final newNote = find.byType(NewNoteButton);

/// Opens Settings with Home's gear.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
}

/// Settings' first row: the account.
final accountRow = find.byKey(const ValueKey('account'));

/// Opens Settings, then taps its Account row: the sign-in when signed out, else the Account page.
Future<void> openAccount(WidgetTester tester) async {
  await openSettings(tester);
  await tester.tap(accountRow);
  await tester.pumpAndSettle();
}

/// The title and the line the Account row shows.
List<String?> accountLines(WidgetTester tester) {
  final tile = tester.widget<ListTile>(accountRow);
  return [(tile.title! as Text).data, (tile.subtitle as Text?)?.data];
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

/// A tap in the middle of the recording screen, which saves the voice note.
Future<void> tapAnywhere(WidgetTester tester) async {
  await tester.tapAt(tester.getCenter(find.byType(RecordingScreen)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// The X at the top right of the recording screen, which keeps nothing.
final cancelX = find.byTooltip('Cancel');

/// The heights of the recording screen's sound bars, left to right.
List<double> barHeights(WidgetTester tester) => [
  for (final bar in find.descendant(of: find.byType(LevelBars), matching: find.byType(AnimatedContainer)).evaluate())
    tester.getSize(find.byWidget(bar.widget)).height,
];

/// The microphone on a voice note's row, not the one on *New note*.
final rowMic = find.byWidgetPredicate((widget) => widget is Icon && widget.semanticLabel == 'Voice note');

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

  /// Scrolls the connect screen's own list until all of [finder] shows.
  Future<void> scrollConnect(WidgetTester tester, Finder finder, [double delta = 100]) async {
    await tester.scrollUntilVisible(finder, delta,
      scrollable: find.descendant(of: find.byType(ConnectScreen), matching: find.byType(Scrollable)).first);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

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

  testWidgets('opens on Home with no key: Notes at 0, the rest Off, no Connections, and Notes keeps a note on this phone',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Sign in'), findsNothing);
    // The header only: with sending off, Home shows no sync line.
    expect(find.text('On this phone'), findsOneWidget);
    expect(countOn('Notes', 0), findsOneWidget);
    for (final gone in ['Voice notes', 'Shares']) {
      expect(find.widgetWithText(ListTile, gone), findsNothing, reason: gone);
    }
    for (final title in ['Location', 'Health', 'Calendar']) {
      expect(find.descendant(of: find.widgetWithText(ListTile, title), matching: find.text('Off')), findsOneWidget, reason: title);
    }
    for (final gone in ['Connections', 'Sending', 'AI apps', 'Webhooks', 'Sign in to see']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    await openFolder(tester, 'Notes');
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Tap New note to write one, or hold it to talk.'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you sign in, in Settings.'), findsOneWidget);
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    await type(tester, 'Buy milk');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, ['note # Buy milk']);
    relay
      ..entries = [Entry(text: 'Buy milk', at: now)]
      ..changed();
    await tester.pump();
    expect([find.text('Buy milk'), find.text('Today'), find.text('1 note')], everyElement(findsOneWidget));
    // A row is the title, the time and the words: no tag, and nothing about sending while it is off.
    expect([find.textContaining('Waiting to send'), find.text('Typed')], everyElement(findsNothing));
  });

  testWidgets('Settings opens on the account card: Sign in to Relay Everything, and a tap opens Sign in with one button and '
      'one link, with no request', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    final asked = relay.refreshes;
    await openSettings(tester);
    expect(accountLines(tester), ['Sign in to Relay Everything', 'Your notes stay on this phone until you sign in.']);
    // The account card comes first, above Appearance.
    expect(tester.getTopLeft(accountRow).dy, lessThan(tester.getTopLeft(find.text('Appearance')).dy));
    expect(find.descendant(of: accountRow, matching: find.byType(RelayMark)), findsOneWidget);
    await tester.tap(accountRow);
    await tester.pumpAndSettle();
    // The one filled Sign in, then the quiet link to the webhook, and no other field or button.
    final buttons = find.descendant(of: find.byType(ListView), matching: find.byWidgetPredicate((widget) => widget is ButtonStyleButton));
    expect(buttons, findsNWidgets(2));
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    expect(find.widgetWithText(TextButton, "Don't want an account? Use your own webhook"), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    for (final gone in ['Scan a key', 'Use another server', 'Send to my own webhook instead', 'Sign in to connect']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.text('Your notes stay on this phone until you sign in.'), findsOneWidget);
    // Back with no key: nothing changed, and nothing asked the network.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect([relay.calls, relay.refreshes, accountLines(tester).first], [isEmpty, asked, 'Sign in to Relay Everything']);
  });

  testWidgets('signs in with one tap, then asks about earlier notes, and the card shows the email and Signed in', (tester) async {
    relay
      ..earlier = 42
      ..server = 'https://app.relayeverything.com';
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('Send your 42 earlier notes too?'), findsOneWidget);
    await tester.tap(find.text('Only new notes'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sign in https://app.relayeverything.com', 'start false']);
    // Back in Settings: with no email from the server yet, the card shows the server.
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(accountLines(tester), ['app.relayeverything.com', 'Signed in']);
    relay
      ..connections = const Connections(email: 'you@example.com', webhooks: ['Zapier'])
      ..settings = relay.settings.copyWith(privateTo: SendPlace.webhook)
      ..changed();
    await tester.pump();
    // Private data to the webhook adds no line.
    expect(accountLines(tester), ['you@example.com', 'Signed in']);
  });

  testWidgets('signs in again with a key kept: asks, and sends earlier notes on a yes', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..earlier = 1;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    // A kept key with sending off reads as signed out.
    expect(accountLines(tester).first, 'Sign in to Relay Everything');
    await tester.tap(accountRow);
    await tester.pumpAndSettle();
    expect(find.text('This phone has a key for https://relay.example.com.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Send your earlier note too?'), findsOneWidget);
    await tester.tap(find.text('Send it'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['start true']);
    // A phone set to another server keeps sending there.
    expect(accountLines(tester), ['relay.example.com', 'Signed in']);
  });

  testWidgets('the sign-in stays open when it is closed, and says why it failed', (tester) async {
    relay.server = 'https://app.relayeverything.com';
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    relay.signsIn = false;
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsOneWidget);
    relay.problem = 'The server did not connect this phone. Sign in and try again.';
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.text('The server did not connect this phone. Sign in and try again.'), findsOneWidget);
    relay
      ..problem = null
      ..signsIn = true;
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sign in https://app.relayeverything.com', 'sign in https://app.relayeverything.com',
      'sign in https://app.relayeverything.com', 'start false']);
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('a row has no tag: a sent note says nothing about sending, and a waiting one says Waiting to send',
      (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..waiting = 1
      ..entries = [
        Entry(text: 'Lunch idea', at: now, waiting: true),
        Entry(text: 'Buy 0.2 mm steel for the stiffener', at: DateTime(2026, 1, 2, 9), sent: true),
      ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect([find.text('Typed'), find.text('Voice'), find.text('Sent'), find.byType(BrandTag)], everyElement(findsNothing));
    expect(find.text('Waiting to send'), findsOneWidget);
    // The waiting line is on the waiting note's row, under its title.
    expect(tester.getTopLeft(find.text('Waiting to send')).dy, greaterThan(tester.getTopLeft(find.text('Lunch idea')).dy));
    expect(tester.getTopLeft(find.text('Waiting to send')).dy,
      lessThan(tester.getTopLeft(find.text('Buy 0.2 mm steel for the stiffener')).dy));
    expect(find.textContaining('Jan 2'), findsOneWidget);
    expect(find.text('2 notes ·'), findsOneWidget);
    expect(find.text('1 waiting'), findsWidgets);
    // The state is words, not a button.
    await tester.tap(find.text('1 waiting').first, warnIfMissed: false);
    await tester.pump();
    expect(relay.calls, isEmpty);
  });

  testWidgets('a voice note row shows a microphone and its length, in accent text, in place of a tag', (tester) async {
    relay.entries = [
      Entry(id: 'v', text: 'Call the fab\nabout the panel', at: now, voice: true, recording: 'voice/v.wav',
        length: const Duration(seconds: 42)),
      Entry(id: 't', text: 'Buy milk', at: now.subtract(const Duration(minutes: 1))),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    final mic = rowMic;
    expect(mic, findsOneWidget);
    expect(tester.widget<Icon>(mic).color, BrandColors.light.accentText);
    expect(find.textContaining('0:42'), findsOneWidget);
    expect(find.textContaining('about the panel'), findsOneWidget);
    expect([find.text('Voice'), find.text('Typed'), find.byType(BrandTag)], everyElement(findsNothing));
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

  testWidgets('no button syncs: Home shows no line when all is sent, 1 waiting while a note waits, and a pull syncs',
      (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..entries = [Entry(text: 'Lunch idea', at: now, sent: true)];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect([find.byType(SyncLine), find.text('Synced'), find.byTooltip('Sync now'), find.byIcon(CupertinoIcons.arrow_2_circlepath)],
      everyElement(findsNothing));
    final open = tester.getBottomLeft(find.text('Home').first).dy;
    relay
      ..waiting = 1
      ..entries = [Entry(text: 'Lunch idea', at: now, waiting: true)]
      ..changed();
    await tester.pump();
    expect(find.descendant(of: find.byType(SyncLine), matching: find.text('1 waiting')), findsOneWidget);
    expect(find.byTooltip('Sync now'), findsNothing);
    // The line makes room under the title: the title moves up, not over it.
    expect(tester.getBottomLeft(find.text('Home').first).dy, lessThanOrEqualTo(open));
    await tester.drag(find.text('Notes'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pull']);
    // The list has its own pull.
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Lunch idea'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pull', 'pull']);
    // Once sent, Home has no line again, and the list only its count.
    relay
      ..waiting = 0
      ..entries = [Entry(text: 'Lunch idea', at: now, sent: true)]
      ..changed();
    await tester.pump();
    expect(find.descendant(of: find.byType(SyncLine), matching: find.text('1 note')), findsOneWidget);
    expect(find.textContaining('waiting'), findsNothing);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(SyncLine), findsNothing);
  });

  /// A signed-in person with an iPhone, this phone, a Pixel and a laptop, and two webhooks.
  Connections family() => Connections(email: 'you@example.com', webhooks: const ['My database', 'Zapier'], thisDevice: 'd-iphone',
    devices: [
      ConnectedDevice(id: 'd-iphone', name: 'iPhone', since: DateTime(now.year, 11, 2)),
      ConnectedDevice(id: 'd-pixel', name: 'Pixel', since: DateTime(now.year, 10, 14)),
      ConnectedDevice(id: 'd-laptop', name: 'Laptop', computer: true, since: DateTime(now.year, 11, 8)),
    ]);

  void signedIn({SendPlace privateTo = SendPlace.server}) => relay
    ..connected = true
    ..server = 'https://relay.example.com'
    ..settings = Settings(sending: true, health: true, privateTo: privateTo)
    ..connections = family();

  testWidgets('the Account page shows the email with Sign out, the phones, Advanced and Delete my account, in that order',
      (tester) async {
    tallScreen(tester);
    final opened = <Uri>[];
    var opens = true;
    signedIn();
    await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
      opened.add(address);
      return opens;
    }));
    await openSettings(tester);
    expect(accountLines(tester), ['you@example.com', 'Signed in']);
    final asked = relay.refreshes;
    await tester.tap(accountRow);
    await tester.pumpAndSettle();
    // The page asks the server for the names again as it opens.
    expect(relay.refreshes, asked + 1);
    final tops = [for (final text in ['you@example.com', 'Phones', 'Advanced', 'Delete my account'])
      tester.getTopLeft(find.text(text)).dy];
    expect(tops, orderedEquals([...tops]..sort()));
    expect(find.descendant(of: find.widgetWithText(ListTile, 'iPhone'), matching: find.text('This phone')), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'iPhone'), matching: find.text('Sign out')), findsNothing);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'Pixel'), matching: find.text('Since Oct 14')), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'Pixel'), matching: find.text('Sign out')), findsOneWidget);
    expect(find.descendant(of: find.widgetWithText(ListTile, 'you@example.com'), matching: find.text('Signed in')), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsNWidgets(2));
    expect(countOn('Webhooks', 2), findsOneWidget);
    expect(find.text('Send a copy to your own server'), findsOneWidget);
    // Computers show in Connect your AI; no filled button, and no question of where data goes.
    for (final gone in ['Laptop', 'Server', 'Open your Relay Everything page', 'AI apps', 'Health, places, calendar and photos',
        'Only to my own webhook', 'API keys']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.byType(FilledButton), findsNothing);
    final delete = find.text('Delete my account');
    expect(tester.widget<Text>(delete).style?.color, Theme.of(tester.element(delete)).colorScheme.error);
    await tester.tap(delete);
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://relay.example.com/#account')]);
    opens = false;
    await tester.tap(delete);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The browser did not open. Try again.'), findsOneWidget);
    expect(relay.calls, isEmpty);
  });

  testWidgets('Sign out beside another phone asks first: Cancel changes nothing, and a yes signs out that phone alone',
      (tester) async {
    tallScreen(tester);
    signedIn();
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    final pixel = find.descendant(of: find.widgetWithText(ListTile, 'Pixel'), matching: find.text('Sign out'));
    await tester.tap(pixel);
    await tester.pumpAndSettle();
    expect(find.text('Sign out Pixel?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect([relay.calls, find.text('Pixel').evaluate().length], [isEmpty, 1]);
    await tester.tap(pixel);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Sign out')));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sign out d-pixel']);
    expect([find.text('Pixel'), find.text('iPhone')], [findsNothing, findsOneWidget]);
    // This phone stays signed in.
    expect([relay.connected, relay.settings.sending], [isTrue, isTrue]);
  });

  testWidgets('Sign out beside the email asks first, then forgets the key, stops sending and goes back to Settings', (tester) async {
    tallScreen(tester);
    signedIn();
    relay.entries = [Entry(text: 'Buy milk', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    final signOut = find.descendant(of: find.widgetWithText(ListTile, 'you@example.com'), matching: find.text('Sign out'));
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
    await tester.tap(signOut);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.widgetWithText(TextButton, 'Sign out')));
    await tester.pumpAndSettle();
    expect(relay.calls, ['disconnect']);
    expect([relay.connected, relay.settings.sending], [isFalse, isFalse]);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(accountLines(tester).first, 'Sign in to Relay Everything');
    // The fake keeps the notes as the app does: signing out deletes none of this phone's notes.
    expect(relay.entries, hasLength(1));
  });

  group('Webhooks, and where health, places, calendar and photos go', () {
    const note = 'What already went to Relay Everything stays on your page. Your AI apps and your page show none of this '
      'from now on.';
    const only = 'Only to my own webhook';
    bool on(WidgetTester tester) => switchOf(tester, only).value;

    Future<void> openWebhooks(WidgetTester tester) async {
      await openAccount(tester);
      await tester.tap(find.text('Webhooks'));
      await tester.pumpAndSettle();
    }

    testWidgets('Webhooks says it is for developers, lists the names, opens the page, and holds the switch, off',
        (tester) async {
      tallScreen(tester);
      final opened = <Uri>[];
      signedIn();
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openWebhooks(tester);
      expect(find.byType(WebhooksPage), findsOneWidget);
      expect(find.textContaining('For developers.'), findsOneWidget);
      expect(find.textContaining('You do not need it to use Relay Everything.'), findsOneWidget);
      expect([find.text('My database'), find.text('Zapier')], everyElement(findsOneWidget));
      expect(find.text('Health, places, calendar and photos'), findsOneWidget);
      expect(find.text('Straight from this phone. Relay Everything never gets them.'), findsOneWidget);
      expect(on(tester), isFalse);
      expect([find.text(note), find.text('Webhook'), find.byType(FilledButton)], [findsNothing, findsNothing, findsNothing]);
      await tester.tap(find.text('Add or change on your Relay Everything page'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://relay.example.com/#webhooks')]);
      expect(relay.calls, isEmpty);
    });

    testWidgets('the switch with no webhook kept opens the setup; back changes nothing, Save turns it on, and off sends to '
        'Relay Everything', (tester) async {
      tallScreen(tester);
      signedIn();
      await tester.pumpWidget(RelayApp(relay: relay));
      await openWebhooks(tester);
      await tester.tap(find.text(only));
      await tester.pumpAndSettle();
      expect(find.textContaining('Your notes still sync through Relay Everything.'), findsOneWidget);
      expect(find.text('Sign in to Relay Everything instead'), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([relay.calls, on(tester), relay.settings.privateTo], [isEmpty, isFalse, SendPlace.server]);
      await tester.tap(find.text(only));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      // No earlier-notes question and no whole-webhook sending: notes still go to Relay Everything.
      expect(relay.calls, ['webhook https://db.example.com/relay ${relay.webhookSecret}', 'private webhook']);
      expect([relay.settings.place, relay.settings.privateTo, on(tester)], [SendPlace.server, SendPlace.webhook, isTrue]);
      expect([find.text('db.example.com'), find.text(note)], [findsOneWidget, findsOneWidget]);
      await tester.tap(find.widgetWithText(TextButton, 'Send a test'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Your receiver answered 204. It works.'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
      // Off: one tap, with no question, and what waits goes to Relay Everything.
      await tester.tap(find.text(only));
      await tester.pumpAndSettle();
      expect([relay.calls.last, on(tester), find.text(note)], ['private server', isFalse, findsNothing]);
    });

    testWidgets('with a webhook kept, the switch moves at once, and its last failure shows', (tester) async {
      tallScreen(tester);
      signedIn();
      relay
        ..webhookAddress = 'https://db.example.com/relay'
        ..webhookSecret = 'whsec_kept';
      await tester.pumpWidget(RelayApp(relay: relay));
      await openWebhooks(tester);
      await tester.tap(find.text(only));
      await tester.pumpAndSettle();
      expect([relay.calls, on(tester)], [['private webhook'], isTrue]);
      final at = DateTime.now();
      relay
        ..webhookProblem = WebhookProblem(at: at, status: 503)
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text(problemLine(relay.webhookProblem!, at, what: 'Health, places, calendar and photos')), findsOneWidget);
      expect(problemLine(WebhookProblem(at: DateTime(2026, 11, 6, 9, 5), status: 503), DateTime(2026, 11, 6),
        what: 'Health, places, calendar and photos'),
        'Your receiver answered 503 at 09:05. Health, places, calendar and photos wait on this phone until it takes them.');
    });

    testWidgets('a webhook the phone lost asks to set it again, and its setup opens from there', (tester) async {
      tallScreen(tester);
      signedIn(privateTo: SendPlace.webhook);
      relay.privateWebhookMissing = true;
      await tester.pumpWidget(RelayApp(relay: relay));
      await openWebhooks(tester);
      expect([find.text('Set your webhook again'), find.text('Webhook')], [findsOneWidget, findsNothing]);
      expect(find.textContaining('Your health, places, calendar and photos wait here until you do.'), findsOneWidget);
      await tester.tap(find.text('Set your webhook again'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(relay.calls.last, 'private webhook');
      expect([find.text('Set your webhook again'), find.text('db.example.com')], [findsNothing, findsOneWidget]);
    });

    testWidgets('no switch signed out, and the no-account webhook page has no Webhooks row', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(MaterialApp(home: WebhooksPage(relay: relay)));
      expect([find.text(only), find.text('Health, places, calendar and photos')], everyElement(findsNothing));
      expect(find.text('Add or change on your Relay Everything page'), findsOneWidget);
      relay
        ..settings = const Settings(sending: true, place: SendPlace.webhook)
        ..webhookAddress = 'https://db.example.com/relay';
      await tester.pumpWidget(RelayApp(relay: relay));
      await openAccount(tester);
      expect([find.text('Webhooks'), find.text('Phones'), find.text('Health, places, calendar and photos')],
        everyElement(findsNothing));
      expect([find.text('My own webhook'), find.text('Sign in to Relay Everything'), find.text('Stop sending')],
        everyElement(findsOneWidget));
    });

    testWidgets('the folders say their data goes to your webhook', (tester) async {
      tallScreen(tester);
      signedIn(privateTo: SendPlace.webhook);
      final at = DateTime.now();
      relay
        ..settings = relay.settings.copyWith(history: true, calendar: true, photos: true)
        ..healthSent = SendState(at: at, waiting: 3)
        ..pointsSent = SendState(at: at)
        ..calendarSent = SendState(at: at, waiting: 1);
      final time = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
      await tester.pumpWidget(RelayApp(relay: relay));
      for (final (folder, line) in [('Health', 'Sent to your webhook $time · 3 readings waiting'),
          ('Location', 'Sent to your webhook $time · none waiting'),
          ('Calendar', 'Sent to your webhook $time · 1 event waiting'),
          ('Photos', 'Sends new photos, with when and where you took them, to your webhook.')]) {
        await openFolder(tester, folder);
        expect(find.text(line), findsOneWidget, reason: folder);
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(sentLine(SendState(at: at), 'reading', at), 'Sent $time · none waiting');
    });
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

  /// The heading a note's row shows under: *Pinned* or its day.
  String groupOf(WidgetTester tester, String title) {
    final headings = [for (final name in ['Pinned', 'Today', 'Yesterday']) if (find.text(name).evaluate().isNotEmpty) name];
    final row = tester.getTopLeft(find.text(title)).dy;
    return headings.lastWhere((name) => tester.getTopLeft(find.text(name)).dy < row);
  }

  testWidgets('a swipe to the right pins a note and deletes nothing; a swipe on a pinned note unpins it', (tester) async {
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.drag(find.text('Buy milk'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect([relay.calls, find.text('Buy milk').evaluate().length, groupOf(tester, 'Buy milk')], [['pin n1'], 1, 'Pinned']);
    await tester.drag(find.text('Buy milk'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect([relay.calls, groupOf(tester, 'Buy milk'), find.text('Pinned').evaluate()], [['pin n1', 'unpin n1'], 'Today', isEmpty]);
  });

  testWidgets('pinned notes show first under Pinned, newest first, and leave their day; a tap on Pinned folds it', (tester) async {
    relay.entries = [
      Entry(id: 'n1', text: 'Shop', at: now),
      Entry(id: 'n2', text: 'Door code', at: now.subtract(const Duration(days: 1)), pinned: true),
      Entry(id: 'n3', text: 'Call Sam', at: now, pinned: true),
      Entry(id: 'n4', text: 'Plan trip', at: now.subtract(const Duration(days: 1))),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect([for (final title in ['Call Sam', 'Door code', 'Shop', 'Plan trip']) groupOf(tester, title)],
      ['Pinned', 'Pinned', 'Today', 'Yesterday']);
    expect(tester.getTopLeft(find.text('Call Sam')).dy, lessThan(tester.getTopLeft(find.text('Door code')).dy));
    expect(tester.getTopLeft(find.text('Pinned')).dy, lessThan(tester.getTopLeft(find.text('Today')).dy));
    expect(find.descendant(of: find.byType(FoldHeader), matching: find.text('Pinned')), findsOneWidget);
    expect(find.descendant(of: find.byType(FoldHeader), matching: find.byType(InkWell)), findsNothing,
      reason: 'a tap on the heading shows no shade');
    // The heading's own node: a tap at its middle, as VoiceOver or Maestro taps, folds it and opens no note.
    final semantics = tester.ensureSemantics();
    final heading = tester.getSemantics(find.text('Pinned'));
    expect(heading.label, 'Pinned');
    expect(heading.rect.height, lessThan(tester.getSize(find.byType(FoldHeader)).height + 1),
      reason: 'the node covers the heading, not the card below');
    semantics.dispose();
    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['fold Pinned true']);
    expect([find.text('Pinned'), find.text('Call Sam'), find.text('Door code'), find.text('Shop')],
      [findsOneWidget, findsNothing, findsNothing, findsOneWidget]);
    // The phone keeps the fold: a new start draws it folded.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect([find.text('Pinned'), find.text('Call Sam')], [findsOneWidget, findsNothing]);
    await tester.tap(find.text('Pinned'));
    await tester.pumpAndSettle();
    expect([relay.calls.last, find.text('Call Sam').evaluate().length], ['fold Pinned false', 1]);
  });

  testWidgets('search finds pinned notes as others; with no pinned match the list has no Pinned part', (tester) async {
    relay.entries = [
      Entry(id: 'n1', text: 'Door code', at: now, pinned: true),
      Entry(id: 'n2', text: 'Gate code', at: now, pinned: true),
      Entry(id: 'n3', text: 'Buy milk', at: now),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.enterText(find.byType(TextField), 'milk');
    await tester.pumpAndSettle();
    expect([find.text('Pinned'), find.text('Door code'), find.text('Buy milk')], [findsNothing, findsNothing, findsOneWidget]);
    expect(groupOf(tester, 'Buy milk'), 'Today');
    await tester.enterText(find.byType(TextField), 'gate');
    await tester.pumpAndSettle();
    expect([find.text('Pinned'), find.text('Gate code'), find.text('Buy milk')], [findsOneWidget, findsOneWidget, findsNothing]);
  });

  testWidgets('with a screen reader, each note row has its own Pin and Delete actions', (tester) async {
    final semantics = tester.ensureSemantics();
    relay.entries = [Entry(id: 'n1', text: 'Buy milk', at: now), Entry(id: 'n2', text: 'Call Sam', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(tester.getSemantics(find.text('Call Sam')), isSemantics(customActions: [const CustomSemanticsAction(label: 'Pin'),
      const CustomSemanticsAction(label: 'Delete')]));
    tester.semantics.performAction(find.semantics.byLabel(RegExp('Call Sam')), SemanticsAction.customAction,
      args: CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Pin')));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pin n2']);
    expect(tester.getSemantics(find.text('Call Sam')), isSemantics(customActions: [const CustomSemanticsAction(label: 'Unpin'),
      const CustomSemanticsAction(label: 'Delete')]));
    relay.calls.clear();
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
      Entry(text: 'Paint colours for the hall', at: now, files: const [
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
    await tester.enterText(find.byType(TextField), 'Swatches');
    await tester.pump();
    expect([find.text('Dentist moved to Thursday 3 pm'), find.text('Paint colours for the hall')], [findsNothing, findsOneWidget]);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.text('No notes with "zzz"'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect([find.text('Gift ideas'), find.text('Dentist moved to Thursday 3 pm'), newNote, find.text('Cancel')],
      [findsOneWidget, findsOneWidget, findsOneWidget, findsNothing]);
    expect(relay.calls, isEmpty);
  });

  testWidgets('names each state the person can act on while sending, and an empty timeline in words', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you sign in, in Settings.'), findsNothing);
    Finder onLine(String words) => find.descendant(of: find.byType(SyncLine), matching: find.text(words));
    for (final (status, waiting, label) in [(SyncStatus.refused, 0, 'Key refused'),
      (SyncStatus.offline, 2, '2 waiting'), (SyncStatus.syncing, 3, '3 waiting'), (SyncStatus.idle, 1, '1 waiting')]) {
      relay
        ..status = status
        ..waiting = waiting
        ..changed();
      await tester.pump();
      expect(onLine(label), findsOneWidget, reason: label);
    }
    for (final (status, settings) in [(SyncStatus.syncing, const Settings(sending: true)),
      (SyncStatus.synced, const Settings(sending: true)), (SyncStatus.idle, const Settings(sending: true)),
      (SyncStatus.offline, const Settings(sending: true)), (SyncStatus.offline, const Settings())]) {
      relay
        ..status = status
        ..waiting = 0
        ..settings = settings
        ..changed();
      await tester.pump();
      expect(find.descendant(of: find.byType(SyncLine), matching: find.byType(Text)).evaluate().map((e) => (e.widget as Text).data),
        ['No notes'], reason: '$status');
    }
    for (final words in ['Syncing', 'Synced', 'On this phone', 'Sync now', 'Offline']) {
      expect(find.text(words), findsNothing, reason: words);
    }
    relay
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.drag(find.text('No notes yet'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['pull']);
  });

  testWidgets('Home shows no line when all is sent, and 1 waiting with a still dot when the phone asks for less motion',
      (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..status = SyncStatus.synced;
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.byType(SyncLine), findsNothing);
    relay
      ..status = SyncStatus.syncing
      ..waiting = 1
      ..changed();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    expect([find.byType(SyncLine).evaluate().length, tester.hasRunningAnimations], [1, true]);
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    relay.changed();
    await tester.pumpAndSettle();
    expect([find.descendant(of: find.byType(SyncLine), matching: find.text('1 waiting')).evaluate().length,
      tester.hasRunningAnimations], [1, false]);
    relay
      ..status = SyncStatus.synced
      ..waiting = 0
      ..changed();
    await tester.pumpAndSettle();
    expect(find.byType(SyncLine), findsNothing);
  });

  testWidgets('scrolled, the top is one row: the small title with 12 notes, and 3 waiting in its place while notes wait',
      (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..status = SyncStatus.synced
      ..entries = [for (var i = 0; i < 12; i++) Entry(text: 'Note $i', at: now.subtract(Duration(minutes: i)))];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    final bar = find.byType(SliverAppBar);
    // The bar's own card: as tall as the top is now.
    final card = find.descendant(of: bar, matching: find.byType(Material)).first;
    final open = tester.getSize(card).height;
    await tester.drag(find.text('Note 3'), const Offset(0, -300));
    await tester.pumpAndSettle();
    final shut = tester.getSize(card).height;
    expect(shut, lessThan(open));
    expect(shut, lessThanOrEqualTo(MediaQuery.paddingOf(tester.element(bar)).top + TitleBar.toolbar));
    Finder top(String words) => find.descendant(of: bar, matching: find.text(words));
    // One row: the small title, and the count under it, in the row's height.
    expect([top('Notes'), top('12 notes')], everyElement(findsOneWidget));
    expect(tester.getBottomLeft(top('12 notes')).dy, lessThanOrEqualTo(tester.getBottomLeft(card).dy));
    expect(find.byType(SyncLine), findsNothing);
    relay
      ..status = SyncStatus.offline
      ..waiting = 3
      ..changed();
    await tester.pump();
    expect([top('12 notes'), top('3 waiting')], [findsNothing, findsOneWidget]);
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 600));
    await tester.pumpAndSettle();
    expect(tester.getSize(card).height, open);
  });

  testWidgets('Home has no line while all is sent, at the top or scrolled', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true)
      ..status = SyncStatus.synced;
    await tester.pumpWidget(RelayApp(relay: relay));
    final bar = find.byType(SliverAppBar);
    final words = [for (final text in find.descendant(of: bar, matching: find.byType(Text)).evaluate())
      (text.widget as Text).data];
    expect(words, ['Home']);
    expect(find.byType(SyncLine), findsNothing);
    relay
      ..entries = [for (var i = 0; i < 20; i++) Entry(text: 'Note $i', at: now)]
      ..changed();
    await tester.pump();
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expect([for (final text in find.descendant(of: bar, matching: find.byType(Text)).evaluate()) (text.widget as Text).data],
      ['Home']);
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

    testWidgets('compose from an open note holds only the new note, and Back holds none', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop\nEggs and milk', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      expect(relay.openNote, 'n1');
      await tester.tap(find.byTooltip('New note'));
      await tester.pumpAndSettle();
      expect(relay.openNote, isNot('n1'));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor).evaluate(), relay.openNote], [isEmpty, isNull]);
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
      expect([find.widgetWithText(MenuItemButton, 'Play'), find.widgetWithText(MenuItemButton, 'Copy')],
        [findsNothing, findsOneWidget]);
      expect(relay.calls, isEmpty);
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
      for (final item in ['Copy', 'Delete']) {
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

    testWidgets('typing at the end of a long note keeps the cursor above the tool bar, which sits 6 points over the keyboard',
      (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      relay.entries = [Entry(id: 'n1', text: ['Long', for (var line = 1; line <= 60; line++) 'Line $line'].join('\n'), at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Long'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(find.byType(QuillEditor)) + const Offset(40, 10));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      quill(tester).updateSelection(TextSelection.collapsed(offset: quill(tester).document.length - 1), ChangeSource.local);
      await type(tester, '\nMore');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final bar = tester.getRect(find.byType(FloatingToolBar));
      expect(bar.bottom, 844 - 300 - 6);
      final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
      final caret = editor.getLocalRectForCaret(quill(tester).selection.extent);
      final top = editor.localToGlobal(caret.topLeft).dy, bottom = editor.localToGlobal(caret.bottomLeft).dy;
      expect(top, greaterThan(0));
      expect(bottom, lessThanOrEqualTo(bar.top));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a caret that moves up a long note, as an Undo far up does, stays under the top edge of the page',
      (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      relay.entries = [Entry(id: 'n1', text: ['Long', for (var line = 1; line <= 60; line++) 'Line $line'].join('\n'), at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Long'));
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getTopLeft(find.byType(QuillEditor)) + const Offset(40, 10));
      await tester.pump();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      quill(tester).updateSelection(TextSelection.collapsed(offset: quill(tester).document.length - 1), ChangeSource.local);
      await type(tester, '\nMore');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      final page = tester.getRect(find.byType(SingleChildScrollView));
      final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
      expect(editor.localToGlobal(Offset.zero).dy, lessThan(page.top - 400), reason: 'the page scrolled far down');
      final line2 = quill(tester).document.toPlainText().indexOf('Line 2');
      quill(tester).updateSelection(TextSelection.collapsed(offset: line2), ChangeSource.local);
      await tester.pumpAndSettle();
      final caret = editor.getLocalRectForCaret(quill(tester).selection.extent);
      expect(editor.localToGlobal(caret.topLeft).dy, greaterThanOrEqualTo(page.top));
      expect(editor.localToGlobal(caret.bottomLeft).dy, lessThanOrEqualTo(tester.getRect(find.byType(FloatingToolBar)).top));
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Undo shows only after a change, takes it back with the keyboard up, Redo puts it again, and an undo is kept',
      (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Shop', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Shop'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      expect(editorFocused(tester), isTrue);
      expect([find.byTooltip('Undo'), find.byTooltip('Redo')], everyElement(findsNothing));
      quill(tester).updateSelection(const TextSelection.collapsed(offset: 4), ChangeSource.local);
      await type(tester, ' buy milk');
      expect([find.byTooltip('Undo'), find.byTooltip('Redo')], [findsOneWidget, findsNothing]);
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['edit # Shop buy milk (later)']);
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump();
      expect(markdownOf(tester), '# Shop');
      expect(editorFocused(tester), isTrue);
      expect([find.byTooltip('Undo'), find.byTooltip('Redo')], everyElement(findsOneWidget));
      await tester.tap(find.byTooltip('Redo'));
      await tester.pump();
      expect(markdownOf(tester), '# Shop buy milk');
      await tester.tap(find.byTooltip('Undo'));
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['edit # Shop buy milk (later)', 'edit # Shop (later)']);
      await type(tester, '!');
      expect([find.byTooltip('Undo'), find.byTooltip('Redo')], [findsOneWidget, findsNothing]);
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect([find.byTooltip('Undo'), find.byTooltip('Redo')], everyElement(findsNothing));
    });

    testWidgets('voice note words that come later start Undo from them, not from the empty page', (tester) async {
      final writing = Entry(id: 'v1', text: '', at: now, voice: true, writing: true, recording: 'voice/a.wav');
      relay.entries = [writing];
      await tester.pumpWidget(RelayApp(relay: relay));
      // The list's Writing the words… row never settles, so the page opens as a tap on it would.
      Navigator.of(tester.element(newNote)).push(MaterialPageRoute<void>(builder: (_) => NoteEditor(relay: relay, entry: writing)));
      await tester.pump();
      relay
        ..entries = [Entry(id: 'v1', text: 'Call Sam', at: now, voice: true, recording: 'voice/a.wav')]
        ..changed();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pump();
      expect(find.byTooltip('Undo'), findsNothing);
    });

    testWidgets('⋯ → Pin Note pins the note, which then reads Unpin Note, and its words and time stay', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Door code', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Door code'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Pin Note'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['pin n1']);
      expect([relay.entries.single.pinned, relay.entries.single.text, relay.entries.single.at], [true, 'Door code', now]);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect([find.widgetWithText(MenuItemButton, 'Unpin Note'), find.widgetWithText(MenuItemButton, 'Pin Note')],
        [findsOneWidget, findsNothing]);
      await tester.tap(find.widgetWithText(MenuItemButton, 'Unpin Note'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['pin n1', 'unpin n1']);
    });

    testWidgets('a new note not kept yet offers no Pin Note', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect([for (final item in tester.widgetList<MenuItemButton>(find.byType(MenuItemButton))) (item.child! as Text).data],
        ['Find in Note', 'Copy', 'Delete']);
    });

    testWidgets('Find in Note steps round the matches in any case, says No matches, and ✓ closes it with the words unchanged',
      (tester) async {
      const text = 'Trip\nTrain at 9\nthe train back\nno train on Sunday';
      relay.entries = [Entry(id: 'n1', text: text, at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      final before = markdownOf(tester);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Find in Note'));
      await tester.pumpAndSettle();
      expect([find.byType(FindBar), find.byType(ReadingBar), find.byType(FloatingToolBar)],
        [findsOneWidget, findsNothing, findsNothing]);
      final field = find.descendant(of: find.byType(FindBar), matching: find.byType(TextField));
      expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      final look = tester.widget<TextField>(field).decoration!;
      expect([look.focusedBorder, look.enabledBorder, look.filled], [InputBorder.none, InputBorder.none, false],
        reason: 'the field draws no box inside the pill, as in Apple Notes');
      await tester.enterText(field, 'train');
      await tester.pumpAndSettle();
      final words = quill(tester).document.toPlainText();
      final starts = [words.indexOf('Train'), words.indexOf('train'), words.lastIndexOf('train')];
      TextSelection match(int index) => TextSelection(baseOffset: starts[index], extentOffset: starts[index] + 5);
      expect([find.text('1 of 3').evaluate().length, quill(tester).selection], [1, match(0)]);
      for (final (index, label) in [(1, '2 of 3'), (2, '3 of 3'), (0, '1 of 3')]) {
        await tester.tap(find.byTooltip('Next match'));
        await tester.pumpAndSettle();
        expect([find.text(label).evaluate().length, quill(tester).selection], [1, match(index)], reason: label);
      }
      await tester.tap(find.byTooltip('Previous match'));
      await tester.pumpAndSettle();
      expect([find.text('3 of 3').evaluate().length, quill(tester).selection], [1, match(2)]);
      expect(editorFocused(tester), isFalse);
      await tester.enterText(field, 'plane');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, CupertinoIcons.chevron_down)).onPressed, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, CupertinoIcons.chevron_up)).onPressed, isNull);
      await tester.tap(find.byTooltip('Done'));
      await tester.pumpAndSettle();
      expect([find.byType(FindBar), find.byType(ReadingBar)], [findsNothing, findsOneWidget]);
      expect(quill(tester).selection.isCollapsed, isTrue);
      expect(markdownOf(tester), before);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('a tap in the words while finding ends find mode, and the tool bar, ✓ and Undo come back', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Trip\nTrain at 9', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Find in Note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(FindBar), matching: find.byType(TextField)), 'train');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(QuillEditor));
      await tester.pumpAndSettle();
      expect(editorFocused(tester), isTrue);
      expect([find.byType(FindBar), find.byType(FloatingToolBar), find.byTooltip('Done')],
        [findsNothing, findsOneWidget, findsOneWidget]);
      await type(tester, '!');
      expect(find.byTooltip('Undo'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('Find in Note selects the right letters after a letter whose lowercase is longer, such as İ', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'İİ trip\nBuy MILK and milk', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('İİ trip'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Find in Note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(FindBar), matching: find.byType(TextField)), 'milk');
      await tester.pumpAndSettle();
      final words = quill(tester).document.toPlainText();
      expect([find.text('1 of 2').evaluate().length, quill(tester).selection.textInside(words)], [1, 'MILK']);
      await tester.tap(find.byTooltip('Next match'));
      await tester.pumpAndSettle();
      expect([quill(tester).selection.start, quill(tester).selection.textInside(words)], [words.lastIndexOf('milk'), 'milk']);
    });

    testWidgets('Find in Note scrolls a match far down a long note into view above the find bar', (tester) async {
      tester.view
        ..physicalSize = const Size(390, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      relay.entries = [Entry(id: 'n1', text: ['Long', for (var line = 1; line <= 60; line++) 'Line $line', 'Gate code 4512']
        .join('\n'), at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Long'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(MenuItemButton, 'Find in Note'));
      await tester.pumpAndSettle();
      await tester.enterText(find.descendant(of: find.byType(FindBar), matching: find.byType(TextField)), 'gate');
      await tester.pumpAndSettle();
      final editor = tester.allRenderObjects.whereType<RenderEditor>().first;
      final caret = editor.getLocalRectForCaret(quill(tester).selection.extent);
      expect(editor.localToGlobal(caret.bottomLeft).dy, lessThanOrEqualTo(tester.getRect(find.byType(FindBar)).top));
      expect(editor.localToGlobal(caret.topLeft).dy, greaterThan(0));
    });

    testWidgets('a waiting and a sent note\'s page show only the date, with no tag and no send item in ⋯', (tester) async {
      relay
        ..connected = true
        ..settings = const Settings(sending: true)
        ..entries = [Entry(id: 'n1', text: 'Shop', at: now, waiting: true), Entry(id: 'n2', text: 'Gone', at: now, sent: true)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      for (final title in ['Shop', 'Gone']) {
        await tester.tap(find.text(title));
        await tester.pumpAndSettle();
        expect([find.byType(BrandTag), find.textContaining('Waiting to send'), find.text('Sent'), find.textContaining('Send now'),
          find.text('Sending…')], everyElement(findsNothing), reason: title);
        await tester.tap(find.byTooltip('More'));
        await tester.pumpAndSettle();
        expect([for (final item in tester.widgetList<MenuItemButton>(find.byType(MenuItemButton))) (item.child! as Text).data],
          ['Pin Note', 'Find in Note', 'Copy', 'Delete'], reason: title);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        await tester.pageBack();
        await tester.pumpAndSettle();
      }
      expect(relay.calls, isEmpty);
    });
  });

  testWidgets('turns settings on and says why one could not be', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
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
    expect(relay.calls, ['history true', 'health true']);
  });

  group('photos', () {
    const denied = "Photo access is off. Turn it on in the phone's Settings.";

    final photosSwitch = find.widgetWithText(SwitchListTile, 'Photos');

    // Opens the Photos folder from Home, under On this phone.
    Future<void> openPhotos(WidgetTester tester) => openFolder(tester, 'Photos');

    testWidgets('Home shows a Photos row that says Off or On, and its page says Photos works once you sign in', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(RelayApp(relay: relay));
      expect(find.widgetWithText(ListTile, 'Photos'), findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Photos'), matching: find.text('Off')), findsOneWidget);
      await openPhotos(tester);
      expect(find.text('Photos works once you sign in. Nothing leaves this phone until you do.'), findsOneWidget);
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
      expect([opened, relay.calls], [[Uri.parse('https://relay.example.com/')], isEmpty]);
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

  testWidgets('with location history on, both phones offer What to send, and a pick says what it dropped', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Location');
    expect(find.text('What to send'), findsNothing);
    relay.settings = const Settings(sending: true, history: true);
    relay.changed();
    await tester.pumpAndSettle();
    RadioGroup<LocationSend> group() => tester.widget(find.byType(RadioGroup<LocationSend>));
    expect([find.text('What to send'), find.text('Stays, trips and points'), find.text('Only points')], everyElement(findsOneWidget));
    expect(group().groupValue, LocationSend.all);
    relay.problem = 'The points still waiting on this phone were dropped.';
    await tester.scrollUntilVisible(find.text('Only stays and trips'), 100, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Only stays and trips'));
    await tester.pumpAndSettle();
    expect([relay.calls, group().groupValue], [['send stays'], LocationSend.stays]);
    expect(find.text('The points still waiting on this phone were dropped.'), findsOneWidget);
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
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    await tester.tap(find.text("Don't want an account? Use your own webhook"));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsNothing);
    // The quiet way back to Relay Everything, and out again.
    await scrollConnect(tester, find.text('Sign in to Relay Everything instead'));
    await tester.tap(find.text('Sign in to Relay Everything instead'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    await tester.tap(find.text("Don't want an account? Use your own webhook"));
    await tester.pumpAndSettle();
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
    await scrollConnect(tester, find.widgetWithText(FilledButton, 'Save'));
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('The address must start with https://.'), findsOneWidget);
    relay.problem = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['test https://db.example.com/relay', 'webhook https://db.example.com/relay $secret',
      'webhook https://db.example.com/relay $secret', 'closed webhook']);
  });

  group('signing in from the webhook Account page', () {
    const offer = 'Sync your notes with your page, your AI and your other phones. Health, places, calendar and photos still '
      'go only to your webhook.';
    const told = 'Signed in. To get your notes at your webhook too, add it under Webhooks on your Relay Everything page.';
    void webhookOnly() => relay
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, place: SendPlace.webhook, health: true)
      ..webhookAddress = 'https://db.example.com/relay'
      ..webhookSecret = 'whsec_kept';

    testWidgets('offers Sign in to Relay Everything as a plain row, with no filled button, above Stop sending in red',
        (tester) async {
      tallScreen(tester);
      webhookOnly();
      await tester.pumpWidget(RelayApp(relay: relay));
      await openAccount(tester);
      final signIn = find.widgetWithText(ListTile, 'Sign in to Relay Everything');
      expect([find.text(offer), find.text('Notes from elsewhere'), find.byType(FilledButton)],
        [findsOneWidget, findsNothing, findsNothing]);
      expect(find.descendant(of: signIn, matching: find.byIcon(CupertinoIcons.chevron_forward)), findsOneWidget);
      final stop = find.widgetWithText(ListTile, 'Stop sending');
      expect(tester.getTopLeft(signIn).dy, lessThan(tester.getTopLeft(stop).dy));
      expect(tester.widget<Text>(find.descendant(of: stop, matching: find.text('Stop sending'))).style?.color,
        Theme.of(tester.element(stop)).colorScheme.error);
    });

    testWidgets('signs in, asks about the notes sent to the webhook, keeps the webhook for private data, and says how to get '
        'notes there', (tester) async {
      tallScreen(tester);
      webhookOnly();
      relay.earlier = 12;
      await tester.pumpWidget(RelayApp(relay: relay));
      await openAccount(tester);
      final asked = relay.refreshes;
      await tester.tap(find.text('Sign in to Relay Everything'));
      await tester.pumpAndSettle();
      // Only the sign-in: the phone sends to the webhook already.
      expect([find.widgetWithText(FilledButton, 'Sign in'), find.text("Don't want an account? Use your own webhook")], [findsOneWidget, findsNothing]);
      expect(find.textContaining('Health, places, calendar and photos still go only to your webhook.'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Send your 12 earlier notes too?'), findsOneWidget);
      expect(find.text('They are not on Relay Everything yet. New notes go to your Relay Everything server from now on.'),
        findsOneWidget);
      await tester.tap(find.text('Send them'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['sign in https://app.relayeverything.com', 'start true private webhook']);
      expect(relay.earlierTo, SendPlace.server);
      expect([relay.settings.place, relay.settings.privateTo, relay.settings.privatePlace],
        [SendPlace.server, SendPlace.webhook, SendPlace.webhook]);
      // The signed-in page and the message; Webhooks shows Only to my own webhook on, with the webhook kept.
      expect([find.text('Sign out'), find.text('Webhooks'), find.text(told)], everyElement(findsOneWidget));
      expect(relay.refreshes, greaterThan(asked));
      await tester.tap(find.text('Webhooks'));
      await tester.pumpAndSettle();
      expect(switchOf(tester, 'Only to my own webhook').value, isTrue);
      expect(find.text('db.example.com'), findsOneWidget);
    });

    testWidgets('a closed sign-in, or back, changes nothing', (tester) async {
      tallScreen(tester);
      webhookOnly();
      relay
        ..earlier = 3
        ..signsIn = false;
      await tester.pumpWidget(RelayApp(relay: relay));
      await openAccount(tester);
      await tester.tap(find.text('Sign in to Relay Everything'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      // The person closed the sign-in: the screen stays open, with no key.
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, ['sign in https://app.relayeverything.com']);
      expect([relay.settings.place, relay.settings.privateTo], [SendPlace.webhook, SendPlace.server]);
      expect([find.text(offer), find.text(told), find.text('Send your 3 earlier notes too?')],
        [findsOneWidget, findsNothing, findsNothing]);
    });

    testWidgets('closing the earlier-notes question changes nothing', (tester) async {
      tallScreen(tester);
      webhookOnly();
      relay
        ..earlier = 1
        ..connected = true;
      await tester.pumpWidget(RelayApp(relay: relay));
      await openAccount(tester);
      await tester.tap(find.text('Sign in to Relay Everything'));
      await tester.pumpAndSettle();
      // A key kept already: one tap, and still no way to the webhook's form.
      expect(find.text("Don't want an account? Use your own webhook"), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Send to Relay Everything'));
      await tester.pumpAndSettle();
      expect(find.text('It is not on Relay Everything yet. New notes go to your Relay Everything server from now on.'),
        findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect([relay.calls, relay.settings.place], [isEmpty, SendPlace.webhook]);
      expect([find.text(offer), find.text(told)], [findsOneWidget, findsNothing]);
    });
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

  testWidgets('picks Use your own webhook, asks about earlier notes, and the Account page shows it and its last problem',
    (tester) async {
    tallScreen(tester);
    relay.earlier = 2;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    await tester.tap(find.text("Don't want an account? Use your own webhook"));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Address'), 'https://db.example.com/relay');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('They were only on this phone. New notes go to your webhook from now on.'), findsOneWidget);
    await tester.tap(find.text('Send them'));
    await tester.pumpAndSettle();
    expect(relay.calls.last, 'start true webhook');
    expect(accountLines(tester), ['My own webhook', 'db.example.com']);
    await tester.tap(accountRow);
    await tester.pumpAndSettle();
    expect(find.text('https://db.example.com/relay'), findsOneWidget);
    for (final gone in ['Server', 'Sign out', 'Phones', 'Advanced', 'Webhooks', 'Delete my account', 'Open your Relay Everything page']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    relay.testAnswer = 'Your receiver answered 401. Check that it has this secret.';
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

  testWidgets('Stop sending with My own webhook asks first, stops, and keeps the webhook', (tester) async {
    tallScreen(tester);
    relay
      ..settings = const Settings(sending: true, place: SendPlace.webhook)
      ..webhookAddress = 'https://db.example.com/relay'
      ..webhookSecret = 'whsec_kept';
    await tester.pumpWidget(RelayApp(relay: relay));
    await openAccount(tester);
    final stop = find.widgetWithText(ListTile, 'Stop sending');
    await tester.tap(stop);
    await tester.pumpAndSettle();
    expect(find.text('Stop sending?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
    await tester.tap(stop);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Stop sending'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['stop']);
    expect([relay.webhookAddress, relay.webhookSecret], ['https://db.example.com/relay', 'whsec_kept']);
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(accountLines(tester).first, 'Sign in to Relay Everything');
  });

  testWidgets('Settings shows the Account row, then the Appearance and Voice notes groups, with no lines, no pin, and the version',
      (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    final groups = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(SliverList));
    for (final heading in ['Appearance', 'Voice notes']) {
      expect(find.descendant(of: groups, matching: find.text(heading)), findsOneWidget, reason: heading);
    }
    expect(tester.getTopLeft(find.text('Appearance')).dy, lessThan(tester.getTopLeft(find.text('Voice notes').last).dy));
    expect(find.descendant(of: groups, matching: find.text('Notes')), findsNothing);
    expect(find.text('Pin notes to where I am'), findsNothing);
    for (final segment in ['System', 'Light', 'Dark']) {
      expect(find.text(segment), findsOneWidget, reason: segment);
    }
    expect(find.text('Relay Everything 1.4.0 (91)'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Relay Everything 1.4.0 (91)')).dy, greaterThan(tester.getTopLeft(find.text('Speech model')).dy));
    for (final gone in ['Sending', 'Send my notes', 'Health', 'Calendar', 'Location history', 'Send photos on mobile data']) {
      expect(find.text(gone), findsNothing, reason: gone);
    }
    expect(find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Divider)), findsNothing);
    expect(tester.getTopLeft(accountRow).dy, lessThan(tester.getTopLeft(find.text('Appearance')).dy));
    // The web's Settings lists the same rows, in the same order, less those for the phone alone.
    expect(SettingsRow.on(web: false),
      [SettingsRow.account, SettingsRow.appearance, SettingsRow.voice, SettingsRow.version]);
    expect(SettingsRow.on(web: true), [SettingsRow.account, SettingsRow.appearance]);
  });

  testWidgets('with sending off, a data folder says it works once you sign in, and Sign in opens the sign-in', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    for (final (folder, what) in [('Location', 'Location history'), ('Health', 'Health'), ('Calendar', 'Calendar'),
      ('Photos', 'Photos')]) {
      await openFolder(tester, folder);
      expect(switchOf(tester, what).onChanged, isNull, reason: what);
      expect(find.text('$what works once you sign in. Nothing leaves this phone until you do.'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    await openFolder(tester, 'Health');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    expect(find.byType(ConnectScreen), findsOneWidget);
    expect(find.text("Don't want an account? Use your own webhook"), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
  });

  testWidgets('Home shows one Notes row; the list\'s filters count and show their notes, and a photo does not move a note',
      (tester) async {
    const photo = EntryFile(name: 'receipt.jpg', type: 'image/jpeg', size: 1258291, path: '/nowhere/receipt.jpg');
    relay.entries = [
      for (final words in ['Buy milk', 'Gift ideas', 'Paint the hall']) Entry(text: words, at: now),
      for (final words in ['Call the fab', 'Ask Sam']) Entry(text: words, at: now, voice: true),
      Entry(text: 'Receipt for the lamp', at: now, files: const [photo]),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(countOn('Notes', 6), findsOneWidget);
    for (final gone in ['Voice notes', 'Shares']) {
      expect(find.widgetWithText(ListTile, gone), findsNothing, reason: gone);
    }
    await openFolder(tester, 'Notes');
    expect(find.byType(TimelineScreen), findsOneWidget);
    Finder chip(String label) => find.widgetWithText(ChoiceChip, label);
    expect([chip('All 6'), chip('Voice 2'), chip('Photos and files 1')], everyElement(findsOneWidget));
    expect(tester.widget<ChoiceChip>(chip('All 6')).selected, isTrue);
    expect([for (final words in ['Buy milk', 'Call the fab', 'Receipt for the lamp']) find.text(words)],
      everyElement(findsOneWidget));
    await tester.tap(chip('Voice 2'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip('Voice 2')).selected, isTrue);
    expect([find.text('Call the fab'), find.text('Ask Sam')], everyElement(findsOneWidget));
    expect([find.text('Buy milk'), find.text('Receipt for the lamp')], everyElement(findsNothing));
    expect(find.descendant(of: find.byType(SyncLine), matching: find.text('2 notes')), findsOneWidget);
    await tester.tap(chip('Photos and files 1'));
    await tester.pumpAndSettle();
    expect([find.text('Receipt for the lamp'), find.text('Buy milk'), find.text('Call the fab')],
      [findsOneWidget, findsNothing, findsNothing]);
    // A photo added to a note leaves it where it was in All, and adds it to Photos and files.
    relay.entries = [
      Entry(text: 'Buy milk', at: now, files: const [photo]),
      ...relay.entries.skip(1),
    ];
    relay.changed();
    await tester.pumpAndSettle();
    expect([chip('All 6'), chip('Photos and files 2')], everyElement(findsOneWidget));
    expect(find.text('Buy milk'), findsOneWidget);
    await tester.tap(chip('All 6'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Buy milk')).dy, lessThan(tester.getTopLeft(find.text('Gift ideas')).dy));
    await tester.tap(find.text('Call the fab'));
    await tester.pumpAndSettle();
    // A note opened from the list goes back to it, and the list goes back to Home.
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Notes')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Home')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(countOn('Notes', 6), findsOneWidget);
  });

  testWidgets('with no photo or file, Photos and files says so in words', (tester) async {
    relay.entries = [Entry(text: 'See https://example.com', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay));
    await openFolder(tester, 'Notes');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Photos and files 0'));
    await tester.pumpAndSettle();
    expect([find.text('No photos or files yet'), find.text('A note with a photo or a file shows here.')],
      everyElement(findsOneWidget));
    expect(find.text('See https://example.com'), findsNothing);
  });

  testWidgets('search on Home finds every note, on the phone only; Cancel shows the Notes row again', (tester) async {
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
    expect([find.text('Gift ideas'), find.widgetWithText(ListTile, 'Notes')], everyElement(findsNothing));
    await tester.tap(find.text('Dentist moved to Thursday'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byTooltip('Back'), matching: find.text('Home')), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect([find.widgetWithText(ListTile, 'Notes'), find.text('Call the dentist')], [findsOneWidget, findsNothing]);
    // With a filter picked, search finds that filter's notes only.
    await openFolder(tester, 'Notes');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Voice 1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Search'), 'dentist');
    await tester.pump();
    expect([find.text('Dentist moved to Thursday'), find.text('Call the dentist')], [findsOneWidget, findsNothing]);
    expect(relay.calls, isEmpty);
  });

  testWidgets('a tap on On this phone folds it, and the phone keeps it folded', (tester) async {
    tallScreen(tester);
    relay.settings = const Settings(sending: true, place: SendPlace.webhook);
    await tester.pumpWidget(RelayApp(relay: relay));
    // A section name folds with no grey highlight: no ink sits behind it.
    expect(find.ancestor(of: find.text('On this phone'), matching: find.byType(InkWell)), findsNothing);
    await tester.tap(find.text('On this phone'));
    await tester.pumpAndSettle();
    expect([find.text('Location'), find.text('Health')], everyElement(findsNothing));
    expect(relay.calls, ['fold On this phone true']);
    expect(relay.folded, {'On this phone'});
    // A new start reads what the phone kept.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Location'), findsNothing);
    await tester.tap(find.text('On this phone'));
    await tester.pumpAndSettle();
    expect(find.text('Location'), findsOneWidget);
    expect(relay.folded, isEmpty);
  });

  testWidgets('Home shows one Notes row, On this phone, then Other connections with Connect your AI and Email notes, '
      'which folds', (tester) async {
    tallScreen(tester);
    await tester.pumpWidget(RelayApp(relay: relay));
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    final ai = find.widgetWithText(ListTile, 'Connect your AI');
    final email = find.widgetWithText(ListTile, 'Email notes');
    expect(find.text('Other connections'), findsOneWidget);
    expect(find.descendant(of: ai, matching: find.text('Let your AI read your notes')), findsOneWidget);
    expect(find.descendant(of: email, matching: find.text('Email a note to your own address')), findsOneWidget);
    expect(find.text('AI chat transcripts'), findsNothing);
    expect(top(find.widgetWithText(ListTile, 'Notes')), lessThan(top(find.widgetWithText(ListTile, 'Location'))));
    expect(top(find.widgetWithText(ListTile, 'Photos')), lessThan(top(find.text('Other connections'))));
    expect(top(find.text('Other connections')), lessThan(top(ai)));
    expect(top(ai), lessThan(top(email)));
    expect(find.ancestor(of: find.text('Other connections'), matching: find.byType(InkWell)), findsNothing);
    await tester.tap(find.text('Other connections'));
    await tester.pumpAndSettle();
    expect([ai, email], everyElement(findsNothing));
    expect(find.widgetWithText(ListTile, 'Location'), findsOneWidget, reason: 'each section folds alone');
    expect([relay.calls, relay.folded], [['fold Other connections true'], {'Other connections'}]);
    // A new start reads what the phone kept.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(ai, findsNothing);
    await tester.tap(find.text('Other connections'));
    await tester.pumpAndSettle();
    expect([ai, email], everyElement(findsOneWidget));
    expect(relay.folded, isEmpty);
  });

  group('Connect your AI, Saved chats and Email notes', () {
    const commands = ['/plugin marketplace add matthewwong525/RelayEverything', '/plugin install relay@relay',
      'codex plugin marketplace add matthewwong525/RelayEverything', 'codex plugin add relay@relay', '/relay:connect'];

    /// Keeps what the page copies, as the phone's clipboard would.
    List<String> catchCopies(WidgetTester tester) {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      return copied;
    }

    /// A signed-in phone whose person has this phone, a laptop with the plugin and Claude connected.
    void signedIn({String server = 'https://relay.example.com', Connections? connections}) => relay
      ..connected = true
      ..server = server
      ..settings = const Settings(sending: true)
      ..connections = connections ?? Connections(email: 'you@example.com', thisDevice: 'd-iphone',
        aiApps: [(name: 'Claude', since: DateTime(now.year, 11, 2))],
        devices: [
          ConnectedDevice(id: 'd-iphone', name: 'iPhone', since: DateTime(now.year, 11, 2)),
          const ConnectedDevice(id: 'd-laptop', name: 'Laptop', computer: true),
        ],
        notesAddress: 'notes-k7q2m9@in.example.com', sharedAddress: 'notes@in.example.com', addressesKnown: true);

    testWidgets('signed out, Connect your AI shows the address to copy, Get the plugin and Sign in, and no names',
        (tester) async {
      tallScreen(tester);
      final copied = catchCopies(tester);
      final opened = <Uri>[];
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      await openFolder(tester, 'Connect your AI');
      expect(find.byType(ConnectAiPage), findsOneWidget);
      expect(find.text('Let your AI read your notes, health and places, and add notes when you ask.'), findsOneWidget);
      expect([find.text('Claude Code and Codex'), find.text('Claude, ChatGPT and other AI apps'),
        find.text('mcp.relayeverything.com'), find.text('Add it in your AI app: Settings, Connectors'),
        find.text('Saved chats'), find.text('Get the plugin')], everyElement(findsOneWidget));
      expect([find.text('Laptop'), find.text('Claude'), find.text('Disconnect on your Relay Everything page')],
        everyElement(findsNothing));
      await tester.tap(find.widgetWithText(TextButton, 'Copy'));
      await tester.pump();
      expect([copied, find.text('Copied.').evaluate().length], [['https://mcp.relayeverything.com'], 1]);
      await tester.tap(find.text('Get the plugin'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://relayeverything.com/connections/claude-code/')]);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('signed in, Connect your AI lists the computers and the apps, and sends Disconnect to the page',
        (tester) async {
      tallScreen(tester);
      final opened = <Uri>[];
      signedIn();
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return true;
      }));
      final asked = relay.refreshes;
      await openFolder(tester, 'Connect your AI');
      expect(relay.refreshes, greaterThan(asked));
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Laptop'), matching: find.text('Plugin · no chat saved yet')),
        findsOneWidget);
      expect(find.descendant(of: find.widgetWithText(ListTile, 'Claude'), matching: find.text('Connected Nov 2')),
        findsOneWidget);
      // Phones show on the Account page, not here; another server's connector address is on its own page.
      expect([find.text('iPhone'), find.text('mcp.relayeverything.com'), find.byType(FilledButton)],
        everyElement(findsNothing));
      expect(find.text('Find the address to add on your Relay Everything page.'), findsOneWidget);
      await tester.tap(find.text('Disconnect on your Relay Everything page'));
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://relay.example.com/#ai-apps')]);
      expect(relay.calls, isEmpty);
      expect(computerLine(DateTime(2026, 11, 2), DateTime(2026, 11, 10)), 'Plugin · last chat Nov 2');
      expect(computerLine(DateTime(2026, 11, 9, 23), DateTime(2026, 11, 10, 8)), 'Plugin · saved a chat yesterday');
      expect(computerLine(DateTime(2025, 11, 2), DateTime(2026, 11, 10)), 'Plugin · last chat Nov 2, 2025');
    });

    testWidgets('signed in to Relay Everything itself, the connector address shows', (tester) async {
      tallScreen(tester);
      signedIn(server: 'https://app.relayeverything.com');
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Connect your AI');
      expect(find.text('mcp.relayeverything.com'), findsOneWidget);
      expect(find.text('Find the address to add on your Relay Everything page.'), findsNothing);
    });

    testWidgets('Saved chats, signed out or with your own webhook, gives the steps to copy, and no link', (tester) async {
      tallScreen(tester);
      final copied = catchCopies(tester);
      final opened = <Uri>[];
      for (final (settings, connected) in [(const Settings(), false), (const Settings(), true),
        (const Settings(sending: true, place: SendPlace.webhook), false)]) {
        relay
          ..settings = settings
          ..connected = connected
          ..server = connected ? 'https://relay.example.com' : null;
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
          opened.add(address);
          return true;
        }));
        await openFolder(tester, 'Connect your AI');
        await tester.tap(find.text('Saved chats'));
        await tester.pumpAndSettle();
        expect(find.byType(TranscriptsPage), findsOneWidget);
        expect(find.text('Saved chats'), findsWidgets);
        expect(find.textContaining('saves your Claude Code and Codex chats word for word'), findsOneWidget);
        for (final command in commands) {
          expect(find.text(command), findsOneWidget, reason: command);
        }
        expect(find.textContaining('Then click Connect.'), findsOneWidget);
        expect(find.text('Read them on the web'), findsNothing, reason: '$settings');
      }
      final connect = find.descendant(of: find.widgetWithText(CommandBox, '/relay:connect'), matching: find.byTooltip('Copy'));
      await tester.ensureVisible(connect);
      await tester.tap(connect);
      await tester.pumpAndSettle();
      expect(copied, ['/relay:connect']);
      expect(find.byTooltip('Copied'), findsOneWidget);
      expect([opened, relay.calls], [isEmpty, isEmpty]);
      // Back goes to Connect your AI, then to Home.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectAiPage), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Other connections'), findsOneWidget);
    });

    testWidgets('Saved chats, signed in, Read them on the web opens the saved chats on your Relay Everything page',
        (tester) async {
      tallScreen(tester);
      final opened = <Uri>[];
      var opens = true;
      signedIn();
      await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
        opened.add(address);
        return opens;
      }));
      await openFolder(tester, 'Connect your AI');
      await tester.tap(find.text('Saved chats'));
      await tester.pumpAndSettle();
      final read = find.widgetWithText(FilledButton, 'Read them on the web');
      expect(read, findsOneWidget);
      await tester.ensureVisible(read);
      await tester.tap(read);
      await tester.pumpAndSettle();
      expect(opened, [Uri.parse('https://relay.example.com/#saved-chats')]);
      opens = false;
      await tester.tap(read);
      await tester.pump();
      expect(find.text('The browser did not open. Try again.'), findsOneWidget);
      expect(relay.calls, isEmpty);
    });

    testWidgets('Email notes, signed out, says to sign in and shows no address', (tester) async {
      tallScreen(tester);
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Email notes');
      expect(find.byType(EmailNotesPage), findsOneWidget);
      expect([find.text('Send or forward an email, and it becomes a note, with its files.'),
        find.text('Sign in to get your addresses.'), find.widgetWithText(FilledButton, 'Sign in')], everyElement(findsOneWidget));
      expect(find.textContaining('@'), findsNothing);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.byType(ConnectScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('Email notes, signed in, shows both addresses, each with Copy, and no New address', (tester) async {
      tallScreen(tester);
      final copied = catchCopies(tester);
      signedIn();
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Email notes');
      expect([find.text('From you@example.com'), find.text('notes@in.example.com'),
        find.text('Takes mail only from the email you sign in with.'), find.text('From any address'),
        find.text('notes-k7q2m9@in.example.com')], everyElement(findsOneWidget));
      expect([find.text('New address'), find.byType(FilledButton), find.text('Sign in to get your addresses.')],
        everyElement(findsNothing));
      await tester.tap(find.descendant(of: find.widgetWithText(ListTile, 'notes-k7q2m9@in.example.com'),
        matching: find.text('Copy')));
      await tester.pump();
      expect(copied, ['notes-k7q2m9@in.example.com']);
      expect(find.text('Copied.'), findsOneWidget);
      expect(relay.calls, isEmpty);
    });

    testWidgets('Email notes says when the server takes no email', (tester) async {
      tallScreen(tester);
      signedIn(connections: Connections.fromJson({'email': 'you@example.com', 'notesAddress': null, 'sharedAddress': null}));
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Email notes');
      expect(find.text('Your Relay Everything server does not take email.'), findsOneWidget);
      expect(find.textContaining('in.example.com'), findsNothing);
    });

    testWidgets('Email notes, from a copy kept by an older app or server, shows no address and no "does not take email"',
      (tester) async {
      tallScreen(tester);
      signedIn(connections: Connections.decode('{"email":"you@example.com","aiApps":[],"webhooks":[]}'));
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Email notes');
      expect(find.text('Send or forward an email, and it becomes a note, with its files.'), findsOneWidget);
      expect([find.text('Your Relay Everything server does not take email.'), find.textContaining('in.example.com'),
        find.text('Copy'), find.text('Sign in to get your addresses.')], everyElement(findsNothing));
      expect(relay.calls, isEmpty);
    });
  });

  testWidgets('Home asks the server for the account and names as it opens', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(relay.refreshes, 1);
  });

  test('each Home row says Off, or what the phone knows', () {
    final today = DateTime(now.year, now.month, now.day, 18);
    final fake = FakeRelay();
    expect([locationLine(fake, today), healthLine(fake, today), calendarLine(fake, today), photosLine(fake)],
      ['Off', 'Off', 'Off', 'Off']);
    fake
      ..locationModes = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, history: true, health: true, calendar: true, calendarsOff: {'holidays'})
      ..pointsSent = SendState(at: DateTime(now.year, now.month, now.day, 14, 5))
      ..healthSent = SendState(at: DateTime(now.year, now.month, now.day, 14, 2), waiting: 3)
      ..calendarSent = SendState(at: DateTime(now.year, now.month, now.day, 13, 40));
    expect([locationLine(fake, today), healthLine(fake, today), calendarLine(fake, today)],
      ['Save battery · Sent 14:05', 'Sent 14:02 · 3 waiting', '1 calendar · Sent 13:40']);
    fake
      ..locationModes = false
      ..pointsSent = const SendState(waiting: 2)
      ..settings = const Settings(sending: true, place: SendPlace.webhook, history: true, calendar: true)
      ..webhookAddress = 'https://db.example.com/relay';
    expect([locationLine(fake, today), calendarLine(fake, today)], ['Not sent yet · 2 waiting', '2 calendars · Sent 13:40']);
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
      expect([find.text('Listening'), find.text('Tap anywhere to save'), find.text('Saves by itself at 5:00'), cancelX],
        everyElement(findsOneWidget));
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['voice start']);
      expect(find.text('Listening'), findsOneWidget);
      await tapAnywhere(tester);
      expect(relay.calls, ['voice start', 'voice end']);
      expect([find.text('Listening'), find.byType(NoteEditor)], [findsNothing, findsOneWidget]);
    });

    testWidgets('a tap to save opens the new note: Writing the words, then its words fill in; Back shows Home', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tapAnywhere(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect([find.byType(NoteEditor), find.text('Writing the words…'), find.widgetWithText(TextButton, 'Home')],
        everyElement(findsOneWidget));
      final saved = relay.entries.single;
      relay
        ..entries = [Entry(id: saved.id, text: 'Ask the fab if the flex stiffener can be 0.2 mm', at: saved.at, voice: true,
          recording: saved.recording, length: saved.length)]
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('Writing the words…'), findsNothing);
      expect(quill(tester).document.toPlainText(), 'Ask the fab if the flex stiffener can be 0.2 mm\n');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor), find.byType(TimelineScreen)], [findsNothing, findsNothing]);
      expect(newNote, findsOneWidget);
      // Leaving an unchanged note writes nothing back.
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('a voice note with no speech: its page closes by itself, keeps nothing, and the page under it says so',
        (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await holdNewNote(tester);
      await tapAnywhere(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.widgetWithText(TextButton, 'Back'), findsOneWidget);
      relay
        ..entries = []
        ..changed()
        ..notice('No speech heard. Nothing was saved.');
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor), find.byType(TimelineScreen)], [findsNothing, findsOneWidget]);
      expect(find.text('No speech heard. Nothing was saved.'), findsOneWidget);
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('a note page whose note is gone from the list closes once, and leaving keeps nothing', (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Dentist moved to Thursday 3 pm', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Dentist moved to Thursday 3 pm'));
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      // Two changes with the note gone: the page closes once.
      relay
        ..entries = []
        ..changed()
        ..changed();
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor), find.byType(TimelineScreen)], [findsNothing, findsOneWidget]);
      expect(relay.calls, isEmpty);
    });

    /// Opens the page for [opened], as Home does from the note it found, while the list may have moved on since.
    Future<void> openNoteAsFound(WidgetTester tester, Entry opened) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      Navigator.of(tester.element(newNote)).push(MaterialPageRoute<void>(builder: (_) => NoteEditor(relay: relay, entry: opened)));
      await tester.pump();
    }

    testWidgets('a voice note whose words came before its page opened shows them, not Writing the words', (tester) async {
      final writing = Entry(id: 'v1', text: '', at: now, voice: true, writing: true, recording: 'voice/1.wav',
        length: const Duration(seconds: 4));
      relay.entries = [Entry(id: 'v1', text: 'Ask the fab if the flex stiffener can be 0.2 mm', at: now, voice: true,
        recording: 'voice/1.wav', length: const Duration(seconds: 4))];
      await openNoteAsFound(tester, writing);
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor), find.text('Writing the words…')], [findsOneWidget, findsNothing]);
      expect(quill(tester).document.toPlainText(), 'Ask the fab if the flex stiffener can be 0.2 mm\n');
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('a voice note gone before its page opened closes the page at once, and keeps nothing', (tester) async {
      final writing = Entry(id: 'v1', text: '', at: now, voice: true, writing: true, recording: 'voice/1.wav',
        length: const Duration(seconds: 4));
      relay.entries = [];
      await openNoteAsFound(tester, writing);
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsNothing);
      expect(newNote, findsOneWidget);
      expect([relay.calls, relay.openNote], [isEmpty, isNull]);
    });

    testWidgets('a voice row\'s microphone is accent text, rows wear no tag, and the sound bars wear the spark color',
        (tester) async {
      relay.entries = [Entry(text: 'Spoken', at: now, voice: true), Entry(text: 'Written', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      expect(tester.widget<Icon>(rowMic).color, BrandColors.light.accentText);
      expect([find.byType(BrandTag), find.text('Typed')], everyElement(findsNothing));
      await holdNewNote(tester);
      final bar = tester.widget<AnimatedContainer>(find.descendant(of: find.byType(LevelBars),
        matching: find.byType(AnimatedContainer)).first);
      expect((bar.decoration! as ShapeDecoration).color, BrandColors.light.spark);
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

    testWidgets('the X keeps nothing and does not also save', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.tap(cancelX);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(relay.calls, ['voice start', 'voice cancel']);
      expect([find.byType(RecordingScreen), find.byType(NoteEditor)], [findsNothing, findsNothing]);
    });

    testWidgets('the recording covers the whole app; a tap in its middle saves', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      expect(tester.getSize(find.byType(RecordingScreen)), tester.view.physicalSize / tester.view.devicePixelRatio);
      // The time, the bars and the save line sit in the middle of the screen, not at its left edge.
      final middle = tester.getCenter(find.byType(RecordingScreen)).dx;
      for (final part in [find.text('0:00'), find.byType(LevelBars), find.text('Tap anywhere to save')]) {
        expect(tester.getCenter(part).dx, closeTo(middle, 1));
      }
      expect(find.text('Home').hitTestable(), findsNothing);
      await tapAnywhere(tester);
      expect(relay.calls, ['voice start', 'voice end']);
      expect(find.byType(RecordingScreen), findsNothing);
    });

    testWidgets('the back gesture saves on Home and opens the note, as a tap does', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(relay.calls, ['voice start', 'voice end']);
      expect([find.byType(RecordingScreen), find.byType(NoteEditor)], [findsNothing, findsOneWidget]);
    });

    testWidgets('the back gesture saves on a page over Home, and leaves that page under the note', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await holdNewNote(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(relay.calls, ['voice start', 'voice end']);
      expect([find.byType(RecordingScreen), find.byType(NoteEditor), find.widgetWithText(TextButton, 'Back')],
        [findsNothing, findsOneWidget, findsOneWidget]);
      expect(find.byType(TimelineScreen, skipOffstage: false), findsOneWidget);
    });

    testWidgets('the sound bars follow the level, and a silent microphone keeps them at their floor', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(barHeights(tester), List.filled(levelBars, LevelBars.floor));
      relay.levels.add(1);
      // The bars ease from the frame after the level comes.
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      // All bars follow the current level at once, tallest in the middle.
      final heights = barHeights(tester);
      expect(heights, everyElement(greaterThan(LevelBars.floor)));
      expect(heights[levelBars ~/ 2], greaterThan(heights.first * 3));
      expect(heights[levelBars ~/ 2], greaterThan(heights.last * 3));
      relay.levels.add(0);
      for (var frame = 0; frame < 3; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(barHeights(tester), List.filled(levelBars, LevelBars.floor));
      await tapAnywhere(tester);
    });

    test('each bar follows the current level, tallest in the middle, the same for the same step', () {
      const middle = levelBars ~/ 2;
      for (final step in [0, 1, 7]) {
        final heights = [for (var index = 0; index < levelBars; index++) LevelBars.heightOf(index, 1, step)];
        expect(heights, everyElement(inInclusiveRange(LevelBars.floor, LevelBars.top)));
        expect(heights[middle], greaterThan(LevelBars.top * 0.7));
        expect([heights.first, heights.last], everyElement(lessThan(LevelBars.top * 0.25)));
        expect(LevelBars.heightOf(middle, 1, step), heights[middle]);
        expect(LevelBars.heightOf(middle, 0.5, step), closeTo(heights[middle] / 2, 0.001));
        expect(LevelBars.heightOf(middle, 0, step), LevelBars.floor);
      }
      expect(LevelBars.heightOf(3, 1, 0), isNot(LevelBars.heightOf(3, 1, 1)));
    });

    testWidgets('a side swipe on the recording screen saves', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tester.drag(find.byType(RecordingScreen), const Offset(300, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(relay.calls, ['voice start', 'voice end']);
      expect(find.byType(RecordingScreen), findsNothing);
    });

    testWidgets('Hold to talk shows until the first voice note, and not after', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      expect(find.text('Hold to talk'), findsOneWidget);
      await holdNewNote(tester);
      await tapAnywhere(tester);
      expect(find.text('Hold to talk'), findsNothing);
      await tester.pumpWidget(RelayApp(relay: relay, key: UniqueKey()));
      expect(find.text('Hold to talk'), findsNothing);
    });

    testWidgets('a voice note seen before shows no tip; search hides New note and its tip', (tester) async {
      relay.holdTipSeen = true;
      await tester.pumpWidget(RelayApp(relay: relay));
      expect(find.text('Hold to talk'), findsNothing);
      relay.holdTipSeen = false;
      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect([newNote, find.text('Hold to talk')], [findsNothing, findsNothing]);
    });

    testWidgets('the ring fills while New note is held and empties on an early lift', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      double ring() => (tester.widget<CustomPaint>(find.descendant(of: newNote, matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is HoldRingPainter))).painter! as HoldRingPainter).progress.value;
      expect(ring(), 0);
      final gesture = await tester.startGesture(tester.getCenter(newNote));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(ring(), closeTo(0.5, 0.1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(NoteEditor), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([ring(), relay.calls], [0, isEmpty]);
    });

    testWidgets('with Reduce motion on, the ring still takes the whole hold to fill', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pumpWidget(RelayApp(relay: relay));
      double ring() => (tester.widget<CustomPaint>(find.descendant(of: newNote, matching: find.byWidgetPredicate(
        (widget) => widget is CustomPaint && widget.painter is HoldRingPainter))).painter! as HoldRingPainter).progress.value;
      final gesture = await tester.startGesture(tester.getCenter(newNote));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(ring(), closeTo(0.5, 0.1));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
    });

    testWidgets('a voice note the phone could not keep says so, and the card closes', (tester) async {
      relay.endProblem = 'The voice note did not save.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tapAnywhere(tester);
      expect([find.text('Listening'), find.text('The voice note did not save.')], [findsNothing, findsOneWidget]);
      expect(relay.calls, ['voice start', 'voice end']);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(NoteEditor), findsNothing);
    });

    testWidgets('a recording too short to keep says so', (tester) async {
      relay.endProblem = 'Too short to keep. Nothing was saved.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await holdNewNote(tester);
      await tapAnywhere(tester);
      expect(find.text('Too short to keep. Nothing was saved.'), findsOneWidget);
      expect(relay.calls, ['voice start', 'voice end']);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(NoteEditor), findsNothing);
    });

    testWidgets('a voice note shows Writing the words, then its words, its length and the player', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      // The bar moves until the words come, so the screen never settles while it shows.
      relay
        ..entries = [Entry(text: '', at: now, voice: true, writing: true, recording: 'voice/a.wav',
          length: const Duration(seconds: 12))]
        ..changed();
      await tester.pump();
      expect(rowMic, findsOneWidget);
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
      expect(find.text('Play'), findsNothing);
      await tester.tap(find.byTooltip('Play'));
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
      expect([find.byType(VoicePlayer), find.byTooltip('Play')], [findsNothing, findsNothing]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      relay.notice('No speech heard. Nothing was saved.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No speech heard. Nothing was saved.'), findsOneWidget);
    });

    testWidgets('a note whose words failed says so in the list; its page says the recording is safe and why, keeps the player, and Try again writes them again', (tester) async {
      relay.entries = [Entry(text: '', at: now, voice: true, failed: true, why: 'the speech engine stopped (code -6).',
        recording: 'voice/a.wav', length: const Duration(seconds: 3))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      expect(find.text('The words did not come'), findsOneWidget);
      // The list row gives no reason: only the note's page does.
      expect(find.textContaining('Why:'), findsNothing);
      expect([find.text('Writing the words…'), find.byType(LinearProgressIndicator)], [findsNothing, findsNothing]);
      await tester.tap(find.text('The words did not come'));
      await tester.pumpAndSettle();
      expect(find.text('The words did not come. Your recording is safe.'), findsOneWidget);
      expect(find.text('Why: the speech engine stopped (code -6).'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Why: the speech engine stopped (code -6).')).dy,
        allOf(greaterThan(tester.getTopLeft(find.text('The words did not come. Your recording is safe.')).dy),
          lessThan(tester.getTopLeft(find.text('Try again')).dy)));
      expect([find.text('Writing the words…'), find.byType(LinearProgressIndicator)], [findsNothing, findsNothing]);
      expect(find.byTooltip('Play'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(relay.calls, ['words again']);
      relay.notice('The words did not come. Tap Try again on the note.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('The words did not come. Tap Try again on the note.'), findsOneWidget);
    });

    testWidgets('a failed note with no reason shows no Why line', (tester) async {
      relay.entries = [Entry(text: '', at: now, voice: true, failed: true, recording: 'voice/a.wav',
        length: const Duration(seconds: 3))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('The words did not come'));
      await tester.pumpAndSettle();
      expect([find.text('The words did not come. Your recording is safe.'), find.textContaining('Why:')],
        [findsOneWidget, findsNothing]);
    });

    testWidgets('the player under the date plays and pauses, shows 0:12 / 0:42 while it plays, and a tap on the waves seeks',
        (tester) async {
      relay
        ..waves = [for (var i = 0; i < 48; i++) (i % 6) / 5]
        ..entries = [Entry(id: 'v', text: 'Call the fab', at: now, voice: true, recording: 'voice/v.wav',
          length: const Duration(seconds: 42))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Call the fab'));
      await tester.pumpAndSettle();
      final player = find.byType(VoicePlayer);
      expect(find.descendant(of: player, matching: find.text('0:42')), findsOneWidget);
      // Under the date, above the words.
      expect(tester.getTopLeft(player).dy, lessThan(tester.getTopLeft(find.byType(QuillEditor)).dy));
      expect(tester.widget<CustomPaint>(find.descendant(of: find.byKey(const ValueKey('waves')),
        matching: find.byType(CustomPaint))).painter, isA<WavePainter>().having((wave) => wave.levels, 'levels', hasLength(48)));
      await tester.tap(find.byTooltip('Play'));
      await tester.pump();
      expect(relay.calls, ['play voice/v.wav']);
      expect([find.byTooltip('Pause'), find.byTooltip('Play')], [findsOneWidget, findsNothing]);
      relay.sound.value = const Playback(recording: 'voice/v.wav', at: Duration(seconds: 12), playing: true);
      await tester.pump();
      expect(find.descendant(of: player, matching: find.text('0:12 / 0:42')), findsOneWidget);
      WavePainter painter() => tester.widget<CustomPaint>(find.descendant(of: find.byKey(const ValueKey('waves')),
        matching: find.byType(CustomPaint))).painter! as WavePainter;
      expect(painter().done, closeTo(12 / 42, 0.001));
      expect(painter().played, BrandColors.light.accentText);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(relay.calls.last, 'pause');
      expect(find.byTooltip('Play'), findsOneWidget);
      // A tap at the middle of the waves goes to the middle of the recording.
      await tester.tap(find.byKey(const ValueKey('waves')));
      await tester.pump();
      expect(relay.calls.last, 'seek 21000');
      expect(find.descendant(of: player, matching: find.text('0:21 / 0:42')), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
    });

    testWidgets('a tap on the waves of a stopped recording plays it from there', (tester) async {
      relay.entries = [Entry(id: 'v', text: 'Call the fab', at: now, voice: true, recording: 'voice/v.wav',
        length: const Duration(seconds: 40))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Call the fab'));
      await tester.pumpAndSettle();
      final waves = find.byKey(const ValueKey('waves'));
      await tester.tapAt(tester.getTopLeft(waves) + Offset(tester.getSize(waves).width / 4, 10));
      await tester.pump();
      expect(relay.calls, ['play voice/v.wav', 'seek 10000']);
      expect(find.byTooltip('Pause'), findsOneWidget);
    });

    testWidgets('with no sound waves, such as an m4a, the player draws a plain line that fills as it plays', (tester) async {
      relay.entries = [Entry(id: 'v', text: 'Call the fab', at: now, voice: true, recording: 'voice/v.m4a',
        length: const Duration(seconds: 10))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Call the fab'));
      await tester.pumpAndSettle();
      final paint = find.descendant(of: find.byKey(const ValueKey('waves')), matching: find.byType(CustomPaint));
      expect((tester.widget<CustomPaint>(paint).painter! as WavePainter).levels, isEmpty);
      final rest = (tester.widget<CustomPaint>(paint).painter! as WavePainter).rest;
      void half(Canvas canvas) => WavePainter(levels: const [], done: 0.5, played: BrandColors.light.accentText, rest: rest)
        .paint(canvas, const Size(200, 36));
      expect(half, paints
        ..line(p1: const Offset(0, 18), p2: const Offset(200, 18), color: rest)
        ..line(p1: const Offset(0, 18), p2: const Offset(100, 18), color: BrandColors.light.accentText));
      relay.sound.value = const Playback(recording: 'voice/v.m4a', at: Duration(seconds: 5), playing: true);
      await tester.pump();
      expect((tester.widget<CustomPaint>(paint).painter! as WavePainter).done, 0.5);
    });

    testWidgets('a watch note with no words shows as Voice note with No words heard, a microphone and its length, and no '
        'tag; its page keeps the player, with no Try again', (tester) async {
      relay.entries = [Entry(text: '', at: now, voice: true, noWords: true, recording: 'voice/w.wav',
        length: const Duration(seconds: 6))];
      await tester.pumpWidget(RelayApp(relay: relay));
      await openFolder(tester, 'Notes');
      expect([find.text('Voice note'), find.textContaining('0:06'), find.textContaining('No words heard')],
        everyElement(findsOneWidget));
      expect([find.text('The words did not come'), find.text('Try again'), find.text('Voice'), find.byType(BrandTag)],
        everyElement(findsNothing));
      await tester.tap(find.text('Voice note'));
      await tester.pumpAndSettle();
      expect([find.byType(VoicePlayer), find.byTooltip('Play')], everyElement(findsOneWidget));
      expect(find.text('Try again'), findsNothing);
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
      expect(find.semantics.byPredicate((node) => node.tooltip == 'Cancel' && node.getSemanticsData().hasAction(SemanticsAction.tap)), findsOne);
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
    testWidgets('the paperclip opens a menu with Photos and Files, and adds them to a new note and to an old one', (tester) async {
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
      // A menu beside the button, not a sheet from the bottom.
      expect([find.widgetWithText(MenuItemButton, 'Photos'), find.widgetWithText(MenuItemButton, 'Files')],
        everyElement(findsOneWidget));
      expect(find.byType(BottomSheet), findsNothing);
      final clip = tester.getRect(find.byTooltip('Attach'));
      final menu = tester.getRect(find.widgetWithText(MenuItemButton, 'Photos'));
      expect((menu.center.dy - clip.center.dy).abs(), lessThan(200));
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
      await openFolder(tester, 'Notes');
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

    testWidgets('records at once on the same recording screen; a tap anywhere saves', (tester) async {
      await openWithRequest(tester);
      expect([find.byType(RecordingScreen), find.text('Tap anywhere to save')], everyElement(findsOneWidget));
      expect(relay.holdTipSeen, isTrue);
      expect(relay.calls, ['voice start']);
      await tapAnywhere(tester);
      expect(find.text('Listening'), findsNothing);
      expect(relay.calls, ['voice start', 'voice end']);
      expect(find.byType(NoteEditor), findsOneWidget);
    });

    testWidgets('the X keeps nothing', (tester) async {
      await openWithRequest(tester);
      await tester.tap(cancelX);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect([find.text('Listening'), find.byType(NoteEditor)], [findsNothing, findsNothing]);
      expect(relay.calls, ['voice start', 'voice cancel']);
    });

    testWidgets('records over a folder page that is open; the save opens the note on top, and Back shows the folder',
        (tester) async {
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
      await tester.pump(const Duration(milliseconds: 400));
      expect([find.byType(NoteEditor), find.widgetWithText(TextButton, 'Back')], everyElement(findsOneWidget));
      expect(find.byType(HealthPage), findsNothing);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect([find.byType(NoteEditor), find.byType(HealthPage)], [findsNothing, findsOneWidget]);
    });

    testWidgets('a save over a note page opens the voice note on top; Back gives the hold back to the note under it',
        (tester) async {
      relay.entries = [Entry(id: 'n1', text: 'Dentist moved to Thursday 3 pm', at: now)];
      final requests = StreamController<void>();
      addTearDown(requests.close);
      await tester.pumpWidget(RelayApp(relay: relay, voiceRequests: requests.stream));
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Dentist moved to Thursday 3 pm'));
      await tester.pumpAndSettle();
      expect(relay.openNote, 'n1');
      requests.add(null);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tapAnywhere(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect([find.byType(NoteEditor), find.text('Writing the words…')], everyElement(findsOneWidget));
      expect(relay.openNote, 'voice-1');
      await tester.pageBack();
      await tester.pumpAndSettle();
      // The note page under it still shows, so a pull leaves that note as it is.
      expect(find.byType(NoteEditor), findsOneWidget);
      expect([quill(tester).document.toPlainText(), relay.openNote], ['Dentist moved to Thursday 3 pm\n', 'n1']);
      // The list under it shows the voice note still writing its words, so the screen never settles.
      await tester.pageBack();
      for (var frame = 0; frame < 10; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect([find.byType(NoteEditor).evaluate(), relay.openNote], [isEmpty, isNull]);
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
