import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:relay_app/app.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/background.dart';

import 'fakes.dart';

// With sending off, the app's promise is that nothing leaves the phone. This drives every screen and job with a
// server that fails on any call, a phone that would name places over the network, and health that would read.
void main() {
  testWidgets('with sending off, no screen or job calls the network, names a place, or reads health', (tester) async {
    final store = memoryStore();
    final storage = MemoryStorage();
    final server = noNetwork();
    final places = FakePlaces()..pin = Pin(at: DateTime(2026, 11, 5, 9), lat: 43.65, lon: -79.38, accuracy: 10, place: 'King St W');
    final health = FakeHealth()..readings = [reading(HealthDataType.STEPS, DateTime(2026, 11, 5, 8), DateTime(2026, 11, 5, 9), value: 10)];
    final scheduled = <bool>[];
    final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
      schedule: (on) async => scheduled.add(on));
    await tester.runAsync(relay.load);
    await tester.pumpWidget(RelayApp(relay: relay, scanner: (_) async => null));

    // Settings: pins on (a phone-only fix), and the dependent switches can not turn on.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin notes to where I am'));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Location history'));
    await tester.tap(find.text('Health: steps, heart rate, sleep, workouts'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();

    // A note, pinned.
    await tester.tap(find.text('New note'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Call the PCB fab about the flex stiffener');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    expect(find.text('Call the PCB fab about the flex stiffener'), findsOneWidget);
    expect(find.textContaining('Pinned'), findsOneWidget);
    expect(find.text('On this phone'), findsOneWidget);

    // Pull to refresh, older notes, the app's return and the hourly round.
    await tester.drag(find.text('Call the PCB fab about the flex stiffener'), const Offset(0, 300));
    await tester.runAsync(pumpEventQueue);
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await relay.sync();
      await relay.more();
      expect(await backgroundRound(store, connection: await KeyVault(storage).read(), health: health, sender: Sender(server.api)), isTrue);
      expect(await relay.earlierNotes(), 1);
      expect(await store.outbox(), isEmpty);
      expect(Settings.decode(await store.get(settingsKey), hasKey: false).sending, isFalse);
    });

    expect(server.requests, isEmpty);
    expect(places.named, [false]);
    expect(places.asked, [false]);
    expect(health.reads, isEmpty);
    expect(scheduled, [false]);
    await tester.runAsync(store.close);
  });
}
