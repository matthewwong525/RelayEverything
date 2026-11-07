import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/brand.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/settings.dart' show sentLine;

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
  Future<String?> startSending({required bool sendEarlier}) async {
    calls.add('start $sendEarlier');
    settings = settings.copyWith(sending: true);
    notifyListeners();
    return null;
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
}

final now = DateTime.now();

void main() {
  late FakeRelay relay;
  setUp(() => relay = FakeRelay());

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
  }

  SwitchListTile switchOf(WidgetTester tester, String title) => tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, title));

  testWidgets('shows the mark beside Relay Everything, in the brand colors that follow the phone', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    final bar = find.byType(AppBar);
    expect(find.descendant(of: bar, matching: find.byType(RelayMark)), findsOneWidget);
    expect(find.descendant(of: bar, matching: find.text('Relay Everything')), findsOneWidget);
    RelayMarkPainter painter() => tester.widget<CustomPaint>(
      find.descendant(of: find.byType(RelayMark), matching: find.byType(CustomPaint))).painter! as RelayMarkPainter;
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
    expect(find.text('Connect Relay Everything'), findsNothing);
    expect(find.text('On this phone'), findsOneWidget);
    expect(find.text('No notes yet. Tap New note, or hold to talk.'), findsOneWidget);
    await tester.tap(find.text('New note'));
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
    expect(find.text('Open your Relay Everything page'), findsNothing);
  });

  testWidgets('turns sending on: connects a key first, then asks about earlier notes', (tester) async {
    relay.earlier = 42;
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));
    await openSettings(tester);
    expect(switchOf(tester, 'Health: steps, heart rate, sleep and more').onChanged, isNull);
    await tester.scrollUntilVisible(find.text('Location history'), 100);
    expect(switchOf(tester, 'Location history').onChanged, isNull);
    expect(find.text('Disconnect this phone'), findsNothing);
    expect(find.text('Server'), findsNothing);
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Relay Everything'), findsOneWidget);
    // Back from the connect screen with no key: sending stays off.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(relay.calls, isEmpty);
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'key');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('Send your 42 earlier notes too?'), findsOneWidget);
    await tester.tap(find.text('Only new notes'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['connect key', 'start false']);
    expect(find.text('Settings'), findsOneWidget);
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
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Send your earlier note too?'), findsOneWidget);
    await tester.tap(find.text('Send it'));
    await tester.pumpAndSettle();
    relay.earlier = 0;
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.text('Stop sending?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(relay.settings.sending, isTrue);
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop sending'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['start true', 'stop']);
    // Off and on again with nothing earlier: no prompt.
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(relay.calls, ['start true', 'stop', 'start false']);
  });

  testWidgets('connects by a pasted key, and says why one is refused', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    relay.problem = 'That is not a Relay Everything key.';
    await tester.enterText(find.byType(TextField), 'nonsense');
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(find.text('That is not a Relay Everything key.'), findsOneWidget);
    relay.problem = null;
    await tester.tap(find.text('Connect'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['connect nonsense', 'connect nonsense', 'start false']);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('connects by signing in, to the shared server or another, and stays open when the sign-in is closed', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    await tester.tap(find.text('Send to Relay Everything'));
    await tester.pumpAndSettle();
    relay.signsIn = false;
    await tester.tap(find.text('Sign in to connect'));
    await tester.pumpAndSettle();
    expect(find.text('Connect Relay Everything'), findsOneWidget);
    relay.problem = 'The server did not connect this phone. Sign in and try again.';
    await tester.tap(find.text('Use another server'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'https://relay.example.com');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('The server did not connect this phone. Sign in and try again.'), findsOneWidget);
    relay
      ..problem = null
      ..signsIn = true;
    await tester.tap(find.text('Sign in to connect'));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sign in https://app.relayeverything.com', 'sign in https://relay.example.com',
      'sign in https://app.relayeverything.com', 'start false']);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('connects by a scanned key, and does nothing when the scan is closed', (tester) async {
    String? scanned;
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => scanned));
    await openSettings(tester);
    await tester.tap(find.text('Send to Relay Everything'));
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
    expect(find.text('Show older notes'), findsNothing);
    expect(find.text('1 waiting'), findsOneWidget);
    await tester.tap(find.text('1 waiting'));
    expect(relay.calls, ['sync']);
  });

  testWidgets('with sending on, a card opens the Relay page in the browser; with sending off or no key, it is gone', (tester) async {
    final opened = <Uri>[];
    var opens = true;
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true)
      ..entries = [Entry(text: 'Lunch idea', at: now)];
    await tester.pumpWidget(RelayApp(relay: relay, opener: (address) async {
      opened.add(address);
      return opens;
    }));
    expect(find.text('Ring notes and recordings are on your Relay Everything page.'), findsOneWidget);
    await tester.tap(find.text('Open your Relay Everything page'));
    await tester.pump();
    expect(opened, [Uri.parse('https://relay.example.com/apps/relay/')]);
    opens = false;
    await tester.tap(find.text('Open your Relay Everything page'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('The browser did not open. Try again.'), findsOneWidget);
    relay
      ..settings = const Settings()
      ..changed();
    await tester.pump();
    expect(find.text('Open your Relay Everything page'), findsNothing);
    relay
      ..settings = const Settings(sending: true)
      ..connected = false
      ..server = null
      ..changed();
    await tester.pump();
    expect(find.text('Ring notes and recordings are on your Relay Everything page.'), findsNothing);
    expect([opened, relay.calls], [hasLength(2), isEmpty]);
  });

  testWidgets('names each sync state while sending, and an empty timeline in words', (tester) async {
    relay
      ..connected = true
      ..settings = const Settings(sending: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    expect(find.text('No notes yet. Tap New note, or hold to talk.'), findsOneWidget);
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
    await tester.drag(find.textContaining('No notes yet'), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(relay.calls, ['sync']);
  });

  testWidgets('saves a typed note once it has words', (tester) async {
    await tester.pumpWidget(RelayApp(relay: relay));
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, 'Save');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Buy milk');
    await tester.pump();
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(relay.calls, ['note Buy milk']);
    expect(find.text('New note'), findsOneWidget);
  });

  testWidgets('turns settings on and says why one could not be', (tester) async {
    relay
      ..connected = true
      ..server = 'https://relay.example.com'
      ..settings = const Settings(sending: true, pinNotes: true);
    await tester.pumpWidget(RelayApp(relay: relay));
    await openSettings(tester);
    await tester.tap(find.text('Pin notes to where I am'));
    await tester.ensureVisible(find.text('Location history'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location history'));
    relay.problem = 'Relay Everything may not read your health data.';
    await tester.tap(find.text('Health: steps, heart rate, sleep and more'));
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
    await tester.scrollUntilVisible(find.text('Disconnect this phone'), 100);
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
    expect(switchOf(tester, 'Send to Relay Everything').value, isFalse);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('On this phone'), findsOneWidget);
  });
  group('voice notes', () {
    Finder holdButton() => find.text('Hold to talk');

    testWidgets('hold: the phone listens, and letting go saves', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      final gesture = await tester.startGesture(tester.getCenter(holdButton()));
      await tester.pump();
      expect(relay.calls, ['voice start']);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('Let go to save. Slide off to cancel.'), findsOneWidget);
      await gesture.up();
      await tester.pump();
      expect(relay.calls, ['voice start', 'voice end']);
      expect(find.text('Listening'), findsNothing);
    });

    testWidgets('a short press saves nothing and says to hold', (tester) async {
      relay.endProblem = 'Hold the button while you talk, then let go.';
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(holdButton());
      await tester.pump();
      expect(relay.calls, ['voice start', 'voice end']);
      expect(find.text('Hold the button while you talk, then let go.'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('slide off: the note is cancelled, and letting go then saves nothing', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      final gesture = await tester.startGesture(tester.getCenter(holdButton()));
      await tester.pump();
      await gesture.moveBy(const Offset(-200, -200));
      await tester.pump();
      expect(find.text('Listening'), findsNothing);
      await gesture.up();
      await tester.pump();
      expect(relay.calls, ['voice start', 'voice cancel']);
    });

    testWidgets('a voice note shows Writing the words, then its words, its length and Play', (tester) async {
      relay.entries = [Entry(text: '', at: now, voice: true, writing: true, recording: 'voice/a.wav',
        length: const Duration(seconds: 12))];
      await tester.pumpWidget(RelayApp(relay: relay));
      expect(find.text('Voice'), findsOneWidget);
      expect(find.text('Writing the words…'), findsOneWidget);
      relay
        ..entries = [Entry(text: 'Ask the fab if the flex stiffener can be 0.2 mm', at: now, voice: true,
          recording: 'voice/a.wav', length: const Duration(seconds: 12))]
        ..changed();
      await tester.pumpAndSettle();
      expect(find.text('Writing the words…'), findsNothing);
      expect(find.text('Ask the fab if the flex stiffener can be 0.2 mm'), findsOneWidget);
      expect(find.textContaining('0:12'), findsOneWidget);
      await tester.tap(find.text('Play'));
      expect(relay.calls, ['play voice/a.wav']);
      // A typed note has no Play.
      relay
        ..entries = [Entry(text: 'Typed', at: now)]
        ..changed();
      await tester.pumpAndSettle();
      expect([find.text('Play'), find.text('Voice')], [findsNothing, findsNothing]);
      relay.notice('No speech heard. Nothing was saved.');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No speech heard. Nothing was saved.'), findsOneWidget);
    });

    testWidgets('with no model, a press asks first, and Not now gets nothing', (tester) async {
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(holdButton());
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(find.textContaining('57 MB'), findsOneWidget);
      expect(find.textContaining('Your voice never leaves this phone.'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
      expect(find.textContaining('Getting the speech model'), findsNothing);
    });

    testWidgets('with a screen reader, a tap with no model asks the first-time question once', (tester) async {
      final semantics = tester.ensureSemantics();
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      tester.semantics.tap(find.semantics.byLabel('Hold to talk'));
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
      // A finger's tap still asks once, not twice.
      await tester.tap(holdButton());
      await tester.pumpAndSettle();
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(relay.calls, ['ask model', 'not now', 'ask model']);
      semantics.dispose();
    });

    testWidgets('with a screen reader and the model ready, a tap starts nothing', (tester) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(RelayApp(relay: relay));
      tester.semantics.tap(find.semantics.byLabel('Hold to talk'));
      await tester.pumpAndSettle();
      expect(relay.calls, isEmpty);
      semantics.dispose();
    });

    testWidgets('Get it shows the progress card, and typed notes still work', (tester) async {
      relay.speechModel = ModelState.missing;
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.tap(holdButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Get it'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'get model']);
      expect(find.text('Getting the speech model… 40%'), findsOneWidget);
      expect(find.text('You can type notes now. Voice notes start when it is done.'), findsOneWidget);
      await tester.tap(holdButton());
      await tester.pump();
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
      final gesture = await tester.startGesture(tester.getCenter(holdButton()));
      await tester.pump();
      expect(find.textContaining('may not use the microphone'), findsOneWidget);
      expect(find.text('Listening'), findsNothing);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('Settings shows the model and its size; Remove returns the button to the first-time question', (tester) async {
      await tester.pumpWidget(RelayApp(relay: relay));
      await openSettings(tester);
      expect(find.text('Voice notes'), findsOneWidget);
      expect(find.text('Speech model: on this phone, 57 MB'), findsOneWidget);
      expect(find.text('Your voice is written into words on this phone. Recordings never leave it.'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['remove model']);
      expect(find.text('Remove'), findsNothing);
      expect(find.textContaining('not on this phone'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(holdButton());
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
      await tester.tap(find.text('New note'));
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

    testWidgets('a note shows its pictures small and other files by name and size; a tap opens one', (tester) async {
      relay.entries = [
        Entry(text: 'Receipt for the desk lamp', at: now, files: const [
          EntryFile(name: 'receipt.jpg', type: 'image/jpeg', size: 1258291, path: '/nowhere/receipt.jpg'),
          EntryFile(name: 'warranty.pdf', type: 'application/pdf', size: 245760, path: '/nowhere/warranty.pdf'),
        ]),
        Entry(text: '', at: now, files: const [EntryFile(name: 'only.pdf', type: 'application/pdf', size: 512, path: '/nowhere/only.pdf')]),
      ];
      await tester.pumpWidget(RelayApp(relay: relay));
      await tester.pump();
      expect(find.byTooltip('receipt.jpg'), findsOneWidget);
      expect(find.text('receipt.jpg'), findsNothing);
      expect([find.text('warranty.pdf'), find.text('240 KB'), find.text('only.pdf'), find.text('512 B')],
        everyElement(findsOneWidget));
      // A note of files alone shows no words, and no words about a recording.
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

    testWidgets('opens the recording sheet and records at once; Stop saves', (tester) async {
      await openWithRequest(tester);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('Talk now. Tap Stop to save, or Cancel.'), findsOneWidget);
      expect(relay.calls, ['voice start']);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Recording'), findsNothing);
      expect(relay.calls, ['voice start', 'voice end']);
    });

    testWidgets('Cancel keeps nothing', (tester) async {
      await openWithRequest(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Recording'), findsNothing);
      expect(relay.calls, ['voice start', 'voice cancel']);
    });

    testWidgets('a recording too short to keep says so', (tester) async {
      relay.endProblem = 'Hold the button while you talk, then let go.';
      await openWithRequest(tester);
      await tester.tap(find.text('Stop'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Too short to keep. Nothing was saved.'), findsOneWidget);
    });

    testWidgets('with no speech model, it asks to get it first, as Hold to talk does', (tester) async {
      relay.speechModel = ModelState.missing;
      await openWithRequest(tester);
      expect(find.text('Get the speech model?'), findsOneWidget);
      expect(find.text('Recording'), findsNothing);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(relay.calls, ['ask model', 'not now']);
    });
  });
}
