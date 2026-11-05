import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/background.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/location.dart';

import 'fakes.dart';

final start = DateTime.fromMillisecondsSinceEpoch(1793797200000);
DateTime later(int minutes) => start.add(Duration(minutes: minutes));

void main() {
  group('health', () {
    test('turns each reading into the server\'s sample, by type', () {
      expect(sampleOf(reading(HealthDataType.STEPS, start, later(60), value: 5210)),
        {'type': 'steps', 'start': 1793797200000, 'end': 1793800800000, 'value': 5210.0, 'unit': 'count', 'source': 'com.apple.health'});
      expect(sampleOf(reading(HealthDataType.HEART_RATE, start, start, value: 68))!['unit'], 'bpm');
      expect(sampleOf(reading(HealthDataType.SLEEP_DEEP, start, later(90)))!..remove('source'),
        {'type': 'sleep', 'start': 1793797200000, 'end': 1793802600000, 'value': 90.0, 'unit': 'min'});
      expect(sampleOf(reading(HealthDataType.WORKOUT, start, later(40)))!['value'], 40.0);
      expect(sampleOf(reading(HealthDataType.STEPS, start, later(1), sourceId: ''))!['source'], 'Health');
      expect(sampleOf(reading(HealthDataType.WEIGHT, start, start, value: 70)), isNull);
      expect(sampleOf(reading(HealthDataType.STEPS, start, start, value: -1)), isNull);
    });

    test('reads a week the first time, then again from a little before the last read', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final source = FakeHealth();
      expect(await syncHealth(store, source, now: start), 0);
      expect(source.reads.single, (start.subtract(const Duration(days: 7)), start));
      await syncHealth(store, source, now: later(60));
      expect(source.reads.last, (start.subtract(const Duration(hours: 2)), later(60)));
      expect(await store.waiting(), 0);
    });

    test('sends each reading once, 500 to a batch', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final steps = [for (var i = 0; i < 501; i++) reading(HealthDataType.STEPS, later(i), later(i + 1), value: i)];
      final source = FakeHealth()..readings = [...steps, steps.first];
      expect(await syncHealth(store, source, now: later(600)), 501);
      expect([for (final item in await store.outbox()) (item.route, (item.body['samples'] as List).length)], [('health', 500), ('health', 1)]);
    });
  });

  group('the background round', () {
    test('reads, keeps and sends nothing while sending is off, even with health on from before', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = noNetwork();
      final source = FakeHealth()..readings = [reading(HealthDataType.STEPS, start, later(5), value: 10)];
      await store.set(settingsKey, '{"sending":false,"pinNotes":true,"history":true,"health":true}');
      await store.addNote(LocalNote(clientId: 'note-0001', text: 'x', createdAt: start));
      for (final key in [connection, null]) {
        expect(await backgroundRound(store, connection: key, health: source, sender: Sender(server.api), now: later(60)), isTrue);
      }
      expect([source.reads, server.requests, await store.outbox(), await store.get(healthSince)], [isEmpty, isEmpty, isEmpty, isNull]);
    });

    test('reads health only while sending and health are on, then sends what waits', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer();
      final source = FakeHealth()..readings = [reading(HealthDataType.STEPS, start, later(5), value: 10)];
      await store.set(settingsKey, const Settings(sending: true).encode());
      await store.addPoint(Pin(at: start, lat: 1, lon: 1, accuracy: 1));
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(60)), isTrue);
      expect([source.reads, server.routes], [isEmpty, ['locations']]);
      await store.set(settingsKey, const Settings(sending: true, health: true).encode());
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(60)), isTrue);
      expect([source.reads.length, server.routes.last], [1, 'health']);
      server.answer = (_) => FakeServer.json({}, 503);
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(120)), isFalse);
    });
  });

  group('location', () {
    test('names a place by its street first, then its area', () {
      expect(placeOf(Placemark(thoroughfare: 'King St W', locality: 'Toronto')), 'King St W');
      expect(placeOf(Placemark(thoroughfare: ' ', subLocality: 'Kensington', locality: 'Toronto')), 'Kensington');
      expect(placeOf(Placemark(name: 'x' * 300))!.length, 200);
      expect(placeOf(Placemark()), isNull);
    });

    test('keeps a fix as a pin, with an unknown accuracy as zero', () {
      Position position(double accuracy) => Position(latitude: 43.65, longitude: -79.38, timestamp: start, accuracy: accuracy,
        altitude: 0, altitudeAccuracy: 0, heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0);
      final pin = pinOf(position(12), 'King St W');
      expect([pin.at, pin.lat, pin.lon, pin.accuracy, pin.place], [start, 43.65, -79.38, 12, 'King St W']);
      expect(pinOf(position(double.nan), null).accuracy, 0);
      expect(pinOf(position(-1), null).toJson(), {'at': 1793797200000, 'lat': 43.65, 'lon': -79.38, 'accuracy': 0.0});
    });
  });

  test('a note\'s body carries its pin when it has one', () {
    final pin = Pin(at: start, lat: 1, lon: 2, accuracy: 3);
    expect(LocalNote(clientId: 'note-0001', text: 'x', createdAt: start, pin: pin).toJson(),
      {'clientId': 'note-0001', 'text': 'x', 'createdAt': 1793797200000, 'lat': 1.0, 'lon': 2.0, 'accuracy': 3.0});
  });
}
