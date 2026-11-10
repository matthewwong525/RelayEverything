import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/data/outbox.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/nights.dart';

import 'fakes.dart';

/// 23:00, the evening the made-up night starts.
final evening = DateTime.fromMillisecondsSinceEpoch(1793833200000);
DateTime at(num minutes) => evening.add(Duration(seconds: (minutes * 60).round()));
const week = Duration(days: 7);

const watch = 'com.apple.health.watch';
HealthDataPoint sleep(HealthDataType type, num from, num to) => reading(type, at(from), at(to), sourceId: watch);

/// A watch night from 23:05 to 06:55, as the watch writes it at wake.
final night = [
  sleep(HealthDataType.SLEEP_IN_BED, 5, 475), sleep(HealthDataType.SLEEP_LIGHT, 20, 70),
  sleep(HealthDataType.SLEEP_DEEP, 70, 145), sleep(HealthDataType.SLEEP_REM, 145, 255),
  sleep(HealthDataType.SLEEP_AWAKE, 255, 280), sleep(HealthDataType.SLEEP_LIGHT, 280, 475),
];

/// The nights and samples waiting, by route.
Future<({List<Map> nights, List<Map> samples})> queued(Store store) async {
  final items = await store.outbox();
  List<Map> rows(String route, String list) =>
    [for (final item in items) if (item.route == route) for (final row in item.body[list] as List) row as Map];
  return (nights: rows(nightsRoute, 'nights'), samples: rows('health', 'samples'));
}

/// A store with health asked for and both history reads done, and a last read at [since].
Future<Store> started(DateTime since) async {
  final store = memoryStore();
  addTearDown(store.close);
  final done = since.subtract(const Duration(days: 365)).millisecondsSinceEpoch;
  await store.set(healthTypes, askedTypes);
  await store.set(healthSince, '${since.millisecondsSinceEpoch}');
  await store.set(healthBackfill, '$done');
  await store.set(healthDetail, '$done');
  return store;
}

void main() {
  test('a workout carries its kind, distance and calories; other types do not', () {
    final run = reading(HealthDataType.WORKOUT, at(0), at(32), as: WorkoutHealthValue(
      workoutActivityType: HealthWorkoutActivityType.RUNNING, totalDistance: 5100, totalEnergyBurned: 410));
    expect(sampleOf(run), {'type': 'workout', 'start': at(0).millisecondsSinceEpoch, 'end': at(32).millisecondsSinceEpoch,
      'value': 32.0, 'unit': 'min', 'source': 'com.apple.health', 'kind': 'running', 'distance': 5100.0, 'calories': 410.0});
    final lift = reading(HealthDataType.WORKOUT, at(0), at(45), as: WorkoutHealthValue(
      workoutActivityType: HealthWorkoutActivityType.TRADITIONAL_STRENGTH_TRAINING, totalEnergyBurned: 260));
    expect(sampleOf(lift), allOf(containsPair('kind', 'traditional_strength_training'), containsPair('calories', 260.0),
      isNot(contains('distance'))));
    expect(sampleOf(sleep(HealthDataType.SLEEP_DEEP, 0, 60))!.keys, isNot(contains('kind')));
    // In bed and awake make nights only; they never go as samples.
    expect([sampleOf(night.first), sampleOf(night[4])], [null, null]);
    expect(askedTypes.split(','), containsAll(['sleep', 'workout', 'in_bed', 'awake']));
  });

  test('other types read from 2 hours back; sleep and workouts from 36 hours back', () async {
    final store = await started(at(240));
    final source = FakeHealth();
    await syncHealth(store, source, now: at(300));
    expect([source.reads, source.lateReads], [[(at(120), at(300))], [(at(240).subtract(lateRead), at(300))]]);
  });

  test('a night the watch writes at wake goes whole, from its start', () async {
    // A round ran at 03:00 and found no sleep; at 07:00 the watch writes the night from 23:05.
    final store = await started(at(240));
    final source = FakeHealth()..readings = [...night, reading(HealthDataType.HEART_RATE, at(470), at(470), value: 60)];
    await syncHealth(store, source, now: at(490));
    final sent = await queued(store);
    final made = sent.nights.single;
    expect([made['source'], made['start'], made['end'], made['asleep'], made['awake'], (made['stages'] as List).length],
      [watch, at(5).millisecondsSinceEpoch, at(475).millisecondsSinceEpoch, 430.0, 25.0, 5]);
    // The day's sleep total still comes from the asleep samples, as before; heart rate came from the 2-hour read.
    expect([for (final sample in sent.samples) sample['type']], ['heart_rate', 'sleep', 'sleep', 'sleep', 'sleep']);
  });

  test('a night read again unchanged is not queued again; a changed one is', () async {
    final store = await started(at(480));
    final source = FakeHealth()..readings = night;
    await syncHealth(store, source, now: at(490));
    final first = (await store.outbox()).length;
    await syncHealth(store, source, now: at(550));
    expect((await store.outbox()).length, first);
    // The watch adds a late wake in the night: the night goes again, and only the new reading with it.
    source.readings = [...night, sleep(HealthDataType.SLEEP_AWAKE, 300, 310)];
    await syncHealth(store, source, now: at(610));
    final sent = await queued(store);
    expect([sent.nights.length, sent.nights.last['awake'], sent.samples.length], [2, 35.0, 4]);
    // The list forgets a row 48 hours after its start.
    await syncHealth(store, FakeHealth(), now: at(480).add(const Duration(hours: 49)));
    expect(jsonDecode((await store.get(healthSent))!), isEmpty);
  });

  test('the redo reads a week of sleep and workouts each round, newest first, and ends at 90 days', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final now = at(600);
    await startHealth(store, now);
    expect(await store.get(healthDetail), '${now.millisecondsSinceEpoch}');
    final source = FakeHealth();
    for (var round = 0; round < 20; round++) {
      await syncHealth(store, source, now: now);
    }
    final redo = [for (final read in source.lateReads) if (read != (now.subtract(lateRead), now)) read];
    expect(redo.length, 13);
    // Each week reads 2 hours before it and a day past it, so a night across two weeks is read whole by the older.
    expect(redo.first, (now.subtract(week + edge), now.add(const Duration(days: 1))));
    for (var i = 1; i < redo.length; i++) {
      expect(redo[i].$2, redo[i - 1].$1.add(edge + const Duration(days: 1)));
    }
    expect(await store.get(healthDetail), '${now.subtract(healthHistory).millisecondsSinceEpoch}');
  });

  test('a night across two redo weeks goes once, whole, and a workout with its details', () async {
    final store = await started(at(0));
    final mark = at(-20 * 24 * 60);
    await store.remove(healthSince);
    await store.set(healthDetail, '${mark.millisecondsSinceEpoch}');
    // A night from an hour before the week's start to 7 hours after it, and a run in the week.
    final boundary = mark.subtract(week);
    HealthDataPoint late(HealthDataType type, int from, int to, [HealthValue? as]) =>
      reading(type, boundary.add(Duration(minutes: from)), boundary.add(Duration(minutes: to)), sourceId: watch, as: as);
    final source = FakeHealth()..readings = [late(HealthDataType.SLEEP_LIGHT, -60, 200), late(HealthDataType.SLEEP_DEEP, 200, 420),
      late(HealthDataType.WORKOUT, 600, 640, WorkoutHealthValue(workoutActivityType: HealthWorkoutActivityType.RUNNING,
        totalDistance: 5100))];
    await syncHealth(store, source, now: at(0));
    expect((await queued(store)).nights, isEmpty);
    await syncHealth(store, source, now: at(60));
    final sent = await queued(store);
    expect([sent.nights.single['start'], sent.nights.single['end'], sent.nights.single['asleep']],
      [boundary.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, boundary.add(const Duration(minutes: 420)).millisecondsSinceEpoch,
        480.0]);
    // Each week sends the samples that start in it: the deep sleep and the run first, the light sleep with its week.
    expect([for (final sample in sent.samples) (sample['type'], sample['kind'], sample['distance'])],
      [('sleep', null, null), ('workout', 'running', 5100.0), ('sleep', null, null)]);
  });

  test('an updated phone starts the redo now, once the app asked for the new types', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final source = FakeHealth();
    await store.set(healthSince, '${at(0).millisecondsSinceEpoch}');
    await syncHealth(store, source, now: at(60));
    expect([source.lateReads, await store.get(healthDetail)], [[(at(0).subtract(lateRead), at(60))], isNull]);
    await store.set(healthTypes, askedTypes);
    source.lateReads.clear();
    await syncHealth(store, source, now: at(120));
    expect(source.lateReads.last, (at(120).subtract(week + edge), at(120).add(const Duration(days: 1))));
    expect(await store.get(healthDetail), '${at(120).subtract(week).millisecondsSinceEpoch}');
  });

  test('health or sending turned off forgets the sent list and the redo, and drops waiting nights', () async {
    final store = await started(at(480));
    await syncHealth(store, FakeHealth()..readings = night, now: at(490));
    await stopHealth(store);
    expect([await store.get(healthSent), await store.get(healthDetail)], [null, null]);
    await syncHealth(store, FakeHealth()..readings = night, now: at(500));
    await store.dropReadings();
    expect([await store.get(healthSent), await store.get(healthDetail), await store.outbox()], [null, null, isEmpty]);
  });

  group('the nights route', () {
    final body = {'source': watch, 'start': at(5).millisecondsSinceEpoch, 'end': at(475).millisecondsSinceEpoch,
      'asleep': 430.0, 'core': 245.0, 'deep': 75.0, 'rem': 110.0, 'awake': 25.0, 'stages': []};

    test('goes to the server as POST nights, 30 to a batch, and marks Health sent', () async {
      final store = memoryStore();
      addTearDown(store.close);
      await store.queueNights([for (var i = 0; i < 31; i++) {...body, 'start': i}]);
      final server = FakeServer((_) => FakeServer.json({'received': 1, 'changed': 1}));
      expect((await flush(store, server.api(connection), clock: () => evening)).sent, 2);
      expect([server.routes, (jsonDecode(server.requests.first.body)['nights'] as List).length], [['nights', 'nights'], 30]);
      expect(await store.sentAt(sentHealth), evening);
    });

    test('follows the private place: only my own webhook gets health.nights, and the server nothing', () async {
      final store = memoryStore();
      addTearDown(store.close);
      await store.moveOutbox(relayServer, private: ownWebhook);
      await store.queueNights([body]);
      expect([for (final item in await store.outbox()) item.destination], [ownWebhook]);
      final server = FakeServer((_) => http.Response('', 204));
      expect((await flush(store, server.api(connection))).sent, 0);
      expect((await flush(store, server.webhook(hook, installId), clock: () => evening)).sent, 1);
      final message = jsonDecode(server.requests.single.body) as Map;
      expect([server.requests.single.url.toString(), message['type'], await store.sentAt(sentHealth)],
        [hook.address, 'health.nights', evening]);
    });
  });
}
