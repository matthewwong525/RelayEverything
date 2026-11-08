import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/screens/hold_to_talk.dart';
import 'package:relay_app/sync/background.dart';
import 'package:relay_app/voice/model.dart';

import 'fakes.dart';
import 'screens_test.dart' show holdNewNote, newNote, openSettings;

/// Pumps, with real time between, until [done]: for file work and the model's checksum, which run outside the test's
/// fake time.
Future<void> until(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump();
  }
  expect(done(), isTrue);
}

/// Holds *New note* past [holdToTalk] and lets go, then waits for the real recorder to start.
Future<void> holdUntilListening(WidgetTester tester, bool Function() listening) async {
  final gesture = await tester.startGesture(tester.getCenter(newNote));
  await tester.pump(holdToTalk);
  await gesture.up();
  await until(tester, listening);
}

// With sending off, the app's promise is that nothing leaves the phone. This drives every screen and job, with a key
// kept, against a server that fails on any call, a phone that would name places over the network, and health that would read.
// The one request allowed is the speech model's download, and only after the person's *Get it*.
void main() {
  testWidgets('with sending off, no screen or job calls the network, names a place, or reads health', (tester) async {
    final store = memoryStore();
    final storage = MemoryStorage();
    final server = noNetwork();
    final places = FakePlaces()..pin = Pin(at: DateTime(2026, 11, 5, 9), lat: 43.65, lon: -79.38, accuracy: 10, place: 'King St W');
    final health = FakeHealth()..readings = [reading(HealthDataType.STEPS, DateTime(2026, 11, 5, 8), DateTime(2026, 11, 5, 9), value: 10)];
    final calendar = FakeCalendar()..items = [meeting('a', DateTime(2026, 11, 5, 10))];
    final scheduled = <bool>[];
    final folder = tempFolder();
    final models = ModelServer();
    var clock = DateTime(2026, 11, 5, 9, 41);
    // The iPhone's Swift side, with a point it would hand over, and a sign-in sheet that would open the network.
    final swift = FakeBackground()..lines = [swiftPoint(DateTime(2026, 11, 5, 9), 43.65, -79.38)];
    final webAuth = FakeWebAuth();
    final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
      signInClient: server.client, webAuth: webAuth.call, schedule: (on) async => scheduled.add(on),
      voice: fakeVoice(folder, models, clock: () => clock), native: swift, calendar: calendar);
    // A key is kept, sending is off, and a note written while it was on still waits to send: only the Sender gate
    // keeps that upload on the phone.
    await tester.runAsync(() async {
      await KeyVault(storage).save(connection);
      await store.addNote(LocalNote(clientId: 'waiting', text: 'Written while sending was on', createdAt: DateTime(2026, 11, 4)),
        send: true);
      await store.set(settingsKey, const Settings().encode());
      await relay.load();
    });
    expect([relay.connected, relay.settings.sending], [true, false]);
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));

    // Settings: pins on (a phone-only fix), and the dependent switches can not turn on.
    await openSettings(tester);
    await tester.tap(find.text('Pin notes to where I am'));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Location history'), 100);
    await tester.tap(find.text('Location history'));
    await tester.tap(find.text('Health'));
    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A note, pinned.
    await tester.tap(newNote);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Call the PCB fab about the flex stiffener');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(pumpEventQueue);
    await tester.runAsync(relay.settled);
    await tester.pumpAndSettle();
    expect(find.text('Call the PCB fab about the flex stiffener'), findsOneWidget);
    expect(find.textContaining('Pinned'), findsOneWidget);
    expect(find.text('On this phone'), findsOneWidget);
    expect(find.text('Open your Relay Everything page'), findsNothing);

    // Pull to refresh, the app's return and the hourly round.
    await tester.drag(find.text('Call the PCB fab about the flex stiffener'), const Offset(0, 300));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await relay.sync();
      expect(await backgroundRound(store, connection: await KeyVault(storage).read(), health: health, sender: Sender(server.api),
        native: swift, places: places, calendar: calendar), isTrue);
      expect(await relay.earlierNotes(), 1);
      expect([for (final item in await store.outbox()) item.body['clientId']], ['waiting']);
      expect(Settings.decode(await store.get(settingsKey), hasKey: true).sending, isFalse);
    });

    // Voice notes: the first hold asks, and *Not now* gets nothing.
    await holdNewNote(tester);
    await tester.pumpAndSettle();
    expect(find.text('Get the speech model?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await tester.runAsync(pumpEventQueue);
    expect(models.requests, isEmpty);
    // *Get it*: the model's address, and nothing else.
    await holdNewNote(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Get it'));
    await tester.pump();
    await until(tester, () => relay.speechModel == ModelState.ready);
    await tester.pumpAndSettle();
    expect([for (final request in models.requests) request.url], [modelUrl]);
    expect(models.requests.single.headers.keys.map((key) => key.toLowerCase()), isNot(contains(startsWith('cf-access'))));
    // Hold, let go, talk, tap the screen: the words are written here, and go nowhere.
    await holdUntilListening(tester, () => relay.listening != null);
    expect(find.text('Listening'), findsOneWidget);
    clock = clock.add(const Duration(seconds: 10));
    await tester.tapAt(const Offset(200, 150));
    await until(tester, () => relay.entries.any((entry) => entry.voice && !entry.writing));
    await tester.pumpAndSettle();
    expect(find.text('Ask the fab if the flex stiffener can be 0.2 mm'), findsOneWidget);
    expect(find.text('Voice'), findsOneWidget);
    expect(models.requests, hasLength(1));

    expect(server.requests, isEmpty);
    expect([webAuth.opened, swift.drains, places.lookups], [isEmpty, 0, isEmpty]);
    expect(swift.flags.every((flag) => !flag.health && !flag.history), isTrue);
    expect(places.named, [false]);
    expect(places.asked, [false]);
    expect(health.reads, isEmpty);
    expect([calendar.asked, calendar.listed, calendar.reads], [0, 0, isEmpty]);
    expect(scheduled, [false]);
    await tester.runAsync(store.close);
  });
  testWidgets('with sending off and the model on the phone, a voice note makes no request at all', (tester) async {
    final store = memoryStore();
    final storage = MemoryStorage();
    final server = noNetwork();
    final folder = tempFolder();
    final models = ModelServer();
    var clock = DateTime(2026, 11, 5, 9, 41);
    final relay = RelayController(store: store, vault: KeyVault(storage), places: FakePlaces(), health: FakeHealth(), apiFor: server.api,
      voice: fakeVoice(folder, models, clock: () => clock));
    await tester.runAsync(() async {
      await placeModel(folder);
      await KeyVault(storage).save(connection);
      await store.set(settingsKey, const Settings().encode());
      await relay.load();
    });
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));
    await holdUntilListening(tester, () => relay.listening != null);
    clock = clock.add(const Duration(seconds: 4));
    await tester.tapAt(const Offset(200, 150));
    await until(tester, () => relay.entries.any((entry) => !entry.writing));
    await tester.pumpAndSettle();
    expect(find.text('Ask the fab if the flex stiffener can be 0.2 mm'), findsOneWidget);
    await tester.runAsync(() async {
      await relay.sync();
      expect(await store.outbox(), isEmpty);
      expect(await relay.earlierNotes(), 1);
    });
    expect([server.requests, models.requests], [isEmpty, isEmpty]);
    await tester.runAsync(store.close);
  });

  test('turning sending off deletes waiting calendar uploads, stops reading the calendar, and keeps notes', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final storage = MemoryStorage();
    final server = FakeServer((_) => FakeServer.json({}, 503));
    final calendar = FakeCalendar()..items = [meeting('a', DateTime(2026, 11, 5, 10))];
    final relay = RelayController(store: store, vault: KeyVault(storage), places: FakePlaces(), health: FakeHealth(),
      apiFor: server.api, calendar: calendar, clock: () => DateTime(2026, 11, 5, 9));
    await KeyVault(storage).save(connection);
    await store.set(settingsKey, const Settings(sending: true, calendar: true).encode());
    await relay.load();
    await relay.addNote('Kept');
    await relay.settled();
    expect(await store.waitingEvents(), 1);
    await relay.stopSending();
    final reads = calendar.reads.length;
    await relay.sync();
    expect([relay.settings.calendar, await store.waitingEvents(), await store.calendarSent(), calendar.reads.length],
      [false, 0, isEmpty, reads]);
    expect([for (final item in await store.outbox()) item.route], ['notes']);
  });
}
