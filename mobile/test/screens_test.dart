import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show CustomSemanticsAction, RenderParagraph, SemanticsAction;
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/compose.dart';
import 'package:relay_app/screens/connect.dart';
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/screens/note.dart';
import 'package:relay_app/screens/settings.dart' show SettingsScreen, problemLine, sentLine;

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
  final calls = <String>[];
  String? problem;
  int earlier = 0;

  void changed() => notifyListeners();

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
  @override Future<String?> setHistory(bool on) async { calls.add('history $on'); return problem; }
  @override Future<String?> setHealth(bool on) async { calls.add('health $on'); return problem; }
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
  @override
  Future<String?> addNote(String text, {List<NewFile> files = const []}) async {
    calls.add('note $text${files.isEmpty ? '' : ' + ${[for (final file in files) file.name].join(', ')}'}');
    return null;
  }

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

/// Opens the ⋯ menu, and Settings from it.
Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('More'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Settings'));
  await tester.pumpAndSettle();
}

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

void main() {
  late FakeRelay relay;
  setUp(() => relay = FakeRelay());

  /// Scrolls the connect screen's own list until [finder] shows.
  Future<void> scrollConnect(WidgetTester tester, Finder finder, [double delta = 100]) => tester.scrollUntilVisible(finder, delta,
    scrollable: find.descendant(of: find.byType(ConnectScreen), matching: find.byType(Scrollable)).first);

  SwitchListTile switchOf(WidgetTester tester, String title) => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

  testWidgets('shows the mark above the large Notes title, in the brand colors that follow the phone', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byType(RelayMark)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Notes')), findsWidgets);
    // The large title; the bar's small one shows only once the list scrolls under it.
    expect(tester.renderObjectList<RenderParagraph>(find.text('Notes')).map((title) => title.text.style?.fontSize), contains(32));
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

  testWidgets('opens on the timeline with no key, and keeps a note on this phone', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('Where should the phone send?'), findsNothing);
    expect(find.text('On this phone'), findsOneWidget);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Tap New note to write one, or hold it to talk.'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you turn on sending in Settings.'), findsOneWidget);
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['note Buy milk']);
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
    await openSettings(tester);
    expect(switchOf(tester, 'Health').onChanged, isNull);
    await tester.scrollUntilVisible(find.text('Location history'), 100);
    expect(switchOf(tester, 'Location history').onChanged, isNull);
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
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(switchOf(tester, 'Location history').onChanged, isNotNull);
    await tester.scrollUntilVisible(find.text('Disconnect this phone'), 100);
    expect(find.text('Disconnect this phone'), findsOneWidget);
  });

  testWidgets('turns sending on again with a key kept: asks, and sends earlier notes on a yes', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..earlier = 1;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
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
    await openSettings(tester);
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
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('connects by signing in, to the shared server or another, and stays open when the sign-in is closed', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
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
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('connects by a scanned key, and does nothing when the scan is closed', (tester) async {
    String? scanned;
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => scanned));
    await openSettings(tester);
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
    expect(find.text('Typed'), findsNWidgets(2));
    expect(find.textContaining('King St W · Waiting to send'), findsOneWidget);
    expect(find.textContaining('Harbord St · Sent'), findsOneWidget);
    expect(find.textContaining('Jan 2'), findsOneWidget);
    expect(find.text('2 notes ·'), findsOneWidget);
    expect(find.text('1 waiting'), findsOneWidget);
    await tester.tap(find.text('1 waiting'));
    expect(relay.calls, ['sync']);
  });

  testWidgets('the ⋯ menu holds Settings, and while sending Sync now, and the page only when sending to a server',
      (tester) async {
    final opened = <Uri>[];
    var opens = true;
    relay.entries = [Entry(text: 'Lunch idea', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
      opened.add(address);
      return opens;
    }));
    Future<List<String>> items() async {
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      final shown = [for (final label in ['Settings', 'Sync now', 'Open your Relay Everything page'])
        if (find.widgetWithText(MenuItemButton, label).evaluate().isNotEmpty) label];
      return shown;
    }
    Future<void> close() async {
      await tester.tapAt(const Offset(10, 400));
      await tester.pumpAndSettle();
    }

    expect(await items(), ['Settings']);
    await close();
    relay
      ..settings = const Settings(sending: true, place: SendPlace.webhook)
      ..changed();
    await tester.pump();
    expect(await items(), ['Settings', 'Sync now']);
    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sync']);
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.pump();
    expect(await items(), ['Settings', 'Sync now', 'Open your Relay Everything page']);
    await tester.tap(find.text('Open your Relay Everything page'));
    await tester.pumpAndSettle();
    expect(opened, [Uri.parse('https://relay.example.com/apps/relay/')]);
    opens = false;
    await items();
    await tester.tap(find.text('Open your Relay Everything page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The browser did not open. Try again.'), findsOneWidget);
    expect([opened, relay.calls], [hasLength(2), ['sync']]);
  });

  testWidgets('groups notes by day, newest first, under Today, Yesterday and Previous 7 days', (tester) async {
    relay.entries = [
      Entry(text: 'Ask Sam if the trip moves', at: now),
      Entry(text: 'Paint colours for the hall\nthe warm grey, not the blue.', at: now.subtract(const Duration(days: 1))),
      Entry(text: 'Dentist moved to Thursday', at: now.subtract(const Duration(days: 4))),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
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

  testWidgets('search shows only the notes that hold the words, in any case; Cancel shows them all again', (tester) async {
    relay.entries = [
      Entry(text: 'Dentist moved to Thursday 3 pm', at: now),
      Entry(text: 'Paint colours for the hall', at: now, place: 'Home', files: const [
        EntryFile(name: 'swatches.pdf', type: 'application/pdf', size: 245760, path: '/nowhere/swatches.pdf')]),
      Entry(text: 'Gift ideas', at: now),
    ];
    await tester.pumpWidget(RelayApp(relay: relay));
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
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Notes stay on this phone until you turn on sending in Settings.'), findsNothing);
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
    expect(relay.calls, ['sync']);
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
  });

  testWidgets('saves a typed note once it has words', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(relay.calls, ['note Buy milk']);
    expect(find.byType(ComposeScreen), findsNothing);
    expect(newNote, findsOneWidget);
  });

  testWidgets('the New note page draws the first line bold and keeps the words as typed', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Ideas for the birthday\nthe pottery class');
    await tester.pump();
    final field = tester.widget<TextField>(find.byType(TextField));
    final span = field.controller!.buildTextSpan(context: tester.element(find.byType(TextField)), withComposing: false);
    expect((span.children!.first as TextSpan).style?.fontWeight, FontWeight.w700);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['note Ideas for the birthday\nthe pottery class']);
  });

  group('the New note page keeps the first line bold while the keyboard composes a word', () {
    /// Each piece of text in [span], and whether it is bold and underlined.
    List<(String, bool, bool)> runs(TextSpan span, [TextStyle inherited = const TextStyle()]) {
      final style = inherited.merge(span.style);
      return [
        if (span.text != null) (span.text!, style.fontWeight == FontWeight.w700, style.decoration == TextDecoration.underline),
        for (final child in span.children ?? const <InlineSpan>[]) ...runs(child as TextSpan, style),
      ];
    }

    Future<List<(String, bool, bool)>> composing(WidgetTester tester, TextRange range) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(find.byType(TextField)).controller!;
      controller.value = TextEditingValue(text: 'Ideas for the birthday\nthe pottery class',
        selection: TextSelection.collapsed(offset: range.end), composing: range);
      await tester.pump();
      return runs(controller.buildTextSpan(context: tester.element(find.byType(TextField)), withComposing: true));
    }

    testWidgets('a word in the first line', (tester) async {
      expect(await composing(tester, const TextRange(start: 10, end: 13)), [
        ('Ideas for ', true, false), ('the', true, true), (' birthday', true, false), ('\nthe pottery class', false, false),
      ]);
    });

    testWidgets('a range across the line break', (tester) async {
      expect(await composing(tester, const TextRange(start: 19, end: 26)), [
        ('Ideas for the birth', true, false), ('day', true, true), ('\nthe', false, true), (' pottery class', false, false),
      ]);
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
    await tester.scrollUntilVisible(find.text('Location history'), 100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location history'));
    relay.problem = 'Relay Everything may not read your health data.';
    await tester.scrollUntilVisible(find.text('Health'), -100);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Health'));
    await tester.pump();
    expect(find.text('Relay Everything may not read your health data.'), findsOneWidget);
    expect(relay.calls, ['pin false', 'history true', 'health true']);
  });

  testWidgets('on iPhone, location history offers Save battery or Every 100 m; Android offers no choice', (tester) async {
    relay
      ..connected = true
      ..locationModes = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    expect(find.text('Save battery'), findsNothing);
    relay.settings = const Settings(sending: true, history: true);
    relay.changed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Every 100 m'), 100);
    await tester.pumpAndSettle();
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
    await openSettings(tester);
    await tester.scrollUntilVisible(find.text('Not sent yet · none waiting'), 100);
    expect(find.text('Sent 14:05 · 3 readings waiting'), findsOneWidget);
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
    await openSettings(tester);
    expect(find.text('US Holidays'), findsNothing);
    await tester.scrollUntilVisible(find.text('Calendar'), 100);
    await tester.tap(find.text('Calendar'));
    await tester.pump();
    expect(relay.calls, ['calendar true']);
    relay
      ..settings = const Settings(sending: true, calendar: true)
      ..changed();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('US Holidays'), 100);
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
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    // To the end of Settings: a row scrolled just under the pinned title would not take the tap.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
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
    expect(find.text('On this phone'), findsOneWidget);
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

  testWidgets('in Settings, picks My own webhook, asks about earlier notes, and shows where it sends and its last problem',
    (tester) async {
    relay.earlier = 2;
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
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

  testWidgets('Settings shows three groups with no lines, and with sending off one line says what needs it', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    final groups = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(SliverList));
    for (final heading in ['Notes', 'Voice notes', 'Sending']) {
      expect(find.descendant(of: groups, matching: find.text(heading)), findsOneWidget, reason: heading);
    }
    expect(find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Divider)), findsNothing);
    await tester.scrollUntilVisible(find.text('Health, Calendar and Location history work with Send my notes on.'), 100);
    expect(switchOf(tester, 'Location history').onChanged, isNull);
    expect(find.text('Where you go, also while the app is closed.'), findsOneWidget);
    relay
      ..settings = const Settings(sending: true)
      ..changed();
    await tester.pumpAndSettle();
    expect(find.text('Health, Calendar and Location history work with Send my notes on.'), findsNothing);
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
      expect(find.descendant(of: newNote, matching: find.byIcon(Icons.mic)), findsOneWidget);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Tap anywhere to save.'), findsOneWidget);
      await gesture.up();
      await tester.pump(const Duration(seconds: 2));
      expect(relay.calls, ['voice start']);
      expect(find.text('Listening'), findsOneWidget);
      await tapAnywhere(tester);
      expect(relay.calls, ['voice start', 'voice end']);
      expect([find.text('Listening'), find.byType(ComposeScreen)], [findsNothing, findsNothing]);
    });

    testWidgets('a voice note and Listening wear the spark color; a typed note wears accent soft', (tester) async {
      relay.entries = [Entry(text: 'Spoken', at: now, voice: true), Entry(text: 'Written', at: now)];
      await tester.pumpWidget(RelayApp(relay: relay));
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
      expect(find.byType(ComposeScreen), findsOneWidget);
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
      relay.entries = [Entry(text: '', at: now, voice: true, writing: true, recording: 'voice/a.wav',
        length: const Duration(seconds: 12))];
      await tester.pumpWidget(RelayApp(relay: relay));
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
      expect(find.byType(NoteScreen), findsOneWidget);
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
      expect(find.byType(ComposeScreen), findsOneWidget);
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
    testWidgets('the paperclip adds photos and files as chips: one too big is left out, a chip removes, and Save keeps them',
        (tester) async {
      final picks = <bool>[];
      Future<List<NewFile>> picker({required bool photos}) async {
        picks.add(photos);
        return photos
          ? [const NewFile(path: '/picked/a.jpg', name: 'receipt.jpg', size: 1258291)]
          : [const NewFile(path: '/picked/b.pdf', name: 'warranty.pdf', size: 245760),
              const NewFile(path: '/picked/c.mov', name: 'video.mov', size: 41943040)];
      }
      await tester.pumpWidget(RelayApp(relay: relay, picker: picker));
      await tester.tap(newNote);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add photo or file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos'));
      await tester.pumpAndSettle();
      expect(find.text('receipt.jpg · 1.2 MB'), findsOneWidget);
      // A note can be files alone.
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNotNull);
      await tester.tap(find.text('Add photo or file'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pumpAndSettle();
      expect(find.text('warranty.pdf · 240 KB'), findsOneWidget);
      expect(find.byTooltip('Remove video.mov'), findsNothing);
      expect(find.text('video.mov is over 25 MB, so it was not added.'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove receipt.jpg'));
      await tester.pumpAndSettle();
      expect(find.textContaining('receipt.jpg'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Receipt for the desk lamp');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['note Receipt for the desk lamp + warranty.pdf']);
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
      await tester.pump();
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
