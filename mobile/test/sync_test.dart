import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/background.dart';
import 'package:relay_app/sync/calendar.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/location.dart';
import 'package:relay_app/sync/native.dart';

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
      expect(sampleOf(reading(HealthDataType.BODY_FAT_PERCENTAGE, start, start, value: 20)), isNull);
      expect(sampleOf(reading(HealthDataType.STEPS, start, start, value: -1)), isNull);
    });

    test('turns each new type into the server\'s sample, in its one unit', () {
      (Object?, Object?) of(HealthDataType type, {num value = 0, DateTime? to, HealthValue? as}) {
        final sample = sampleOf(reading(type, start, to ?? start, value: value, as: as))!;
        return (sample['type'], (sample['value'], sample['unit']));
      }
      expect(of(HealthDataType.WEIGHT, value: 70.5), ('weight', (70.5, 'kg')));
      expect(of(HealthDataType.RESTING_HEART_RATE, value: 52), ('resting_heart_rate', (52.0, 'bpm')));
      // The tests run as an iPhone: SDNN and mindful minutes; Android sends RMSSD instead.
      expect(of(HealthDataType.HEART_RATE_VARIABILITY_SDNN, value: 48), ('hrv_sdnn', (48.0, 'ms')));
      expect(sampleOf(reading(HealthDataType.HEART_RATE_VARIABILITY_RMSSD, start, start, value: 40)), isNull);
      // iPhone gives blood oxygen as a fraction, Android as a percent: both go as a percent.
      expect(of(HealthDataType.BLOOD_OXYGEN, value: 0.97), ('blood_oxygen', (97.0, '%')));
      expect(of(HealthDataType.BLOOD_OXYGEN, value: 95), ('blood_oxygen', (95.0, '%')));
      expect(of(HealthDataType.BLOOD_PRESSURE_SYSTOLIC, value: 118), ('blood_pressure_systolic', (118.0, 'mmHg')));
      expect(of(HealthDataType.BLOOD_PRESSURE_DIASTOLIC, value: 76), ('blood_pressure_diastolic', (76.0, 'mmHg')));
      expect(of(HealthDataType.WATER, value: 0.25), ('water', (250.0, 'ml')));
      expect(of(HealthDataType.MINDFULNESS, to: later(10)), ('mindful', (10.0, 'min')));
      MenstruationFlowHealthValue flow(MenstrualFlow? level) => MenstruationFlowHealthValue(flow: level, dateTime: start);
      expect([for (final level in [MenstrualFlow.none, MenstrualFlow.light, MenstrualFlow.medium, MenstrualFlow.heavy,
          MenstrualFlow.unspecified, MenstrualFlow.spotting, null])
        of(HealthDataType.MENSTRUATION_FLOW, as: flow(level))],
        [for (final value in [0.0, 1.0, 2.0, 3.0, 1.0, 1.0, 1.0]) ('cycle_flow', (value, 'flow'))]);
      expect(sampleOf(reading(HealthDataType.MENSTRUATION_FLOW, start, start, value: 2)), isNull);
      expect(askedTypes.split(','), containsAll(['weight', 'cycle_flow', 'hrv_sdnn', 'mindful', 'water']));
    });

    test('reads the last 90 days a week each round, newest first, after the new readings', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final source = FakeHealth();
      await store.set(healthTypes, askedTypes);
      const week = Duration(days: 7);
      // The first round has no last read: it reads the newest week.
      expect(await syncHealth(store, source, now: start), 0);
      expect(source.reads.single, (start.subtract(week), start));
      for (var round = 0; round < 20; round++) {
        await syncHealth(store, source, now: start);
      }
      final reads = source.reads.skip(1).toList();
      // Each round reads since a little before the last, then one week older than the one before it.
      expect(reads.take(2), [(start.subtract(const Duration(hours: 2)), start), (start.subtract(week * 2), start.subtract(week))]);
      final history = [source.reads.first, for (final read in reads) if (read.$2 != start) read];
      expect(history.length, 13);
      for (var i = 1; i < history.length; i++) {
        expect(history[i].$2, history[i - 1].$1);
      }
      expect(history.last.$1, start.subtract(healthHistory));
      expect(await store.get(healthBackfill), '${start.subtract(healthHistory).millisecondsSinceEpoch}');
      expect(await store.waiting(), 0);
    });

    test('a phone updated from before the history read starts it once, at its last read', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final source = FakeHealth();
      final last = start.subtract(const Duration(hours: 1));
      await store.set(healthSince, '${last.millisecondsSinceEpoch}');
      await store.set(healthTypes, askedTypes);
      await syncHealth(store, source, now: start);
      expect(source.reads, [(last.subtract(const Duration(hours: 2)), start), (last.subtract(const Duration(days: 7)), last)]);
      await syncHealth(store, source, now: later(60));
      expect(source.reads.last, (last.subtract(const Duration(days: 14)), last.subtract(const Duration(days: 7))));
    });

    test('an updated phone starts the history read only after the app asked for the new types', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final source = FakeHealth();
      final last = start.subtract(const Duration(hours: 1));
      await store.set(healthSince, '${last.millisecondsSinceEpoch}');
      // A background round before the app opens reads only the new readings, and the history mark stays unset.
      await syncHealth(store, source, now: start);
      await syncHealth(store, source, now: later(60));
      expect(source.reads, [(last.subtract(const Duration(hours: 2)), start), (start.subtract(const Duration(hours: 2)), later(60))]);
      expect(await store.get(healthBackfill), isNull);
      // The app opens and askNewHealthTypes keeps the asked types: the next round starts the history at its last read.
      await store.set(healthTypes, askedTypes);
      source.reads.clear();
      await syncHealth(store, source, now: later(120));
      expect(source.reads, [(later(60).subtract(const Duration(hours: 2)), later(120)),
        (later(60).subtract(const Duration(days: 7)), later(60))]);
      expect(await store.get(healthBackfill), '${later(60).subtract(const Duration(days: 7)).millisecondsSinceEpoch}');
    });

    test('turning health on starts from now, with the history read and the asked types', () async {
      final store = memoryStore();
      addTearDown(store.close);
      await startHealth(store, start);
      expect([await store.get(healthSince), await store.get(healthBackfill), await store.get(healthTypes)],
        ['${start.millisecondsSinceEpoch}', '${start.millisecondsSinceEpoch}', askedTypes]);
      final source = FakeHealth();
      await syncHealth(store, source, now: later(60));
      expect(source.reads, [(start.subtract(const Duration(hours: 2)), later(60)), (start.subtract(const Duration(days: 7)), start)]);
    });

    test('sends each reading once, 500 to a batch', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final steps = [for (var i = 0; i < 501; i++) reading(HealthDataType.STEPS, later(i), later(i + 1), value: i)];
      final source = FakeHealth()..readings = [...steps, steps.first];
      await store.set(healthTypes, askedTypes);
      expect(await syncHealth(store, source, now: later(600)), 501);
      expect([for (final item in await store.outbox()) (item.route, (item.body['samples'] as List).length)], [('health', 500), ('health', 1)]);
    });
  });

  group('calendar', () {
    final now = start;
    const on = Settings(sending: true, calendar: true);
    late Store store;
    late FakeCalendar source;
    setUp(() {
      store = memoryStore();
      source = FakeCalendar();
    });
    tearDown(() => store.close());

    Future<List<Map<String, dynamic>>> uploads() async =>
      [for (final item in await store.outbox()) if (item.route == 'calendar') item.body];
    Future<List<String>> keysSent(int upload, String field) async =>
      [for (final item in (await uploads())[upload][field] as List) item is Map ? item['key'] as String : item as String];

    test('the first round sends the whole window, 90 days back and ahead, from every calendar', () async {
      source.items = [meeting('a', later(60)), meeting('b', now.subtract(const Duration(days: 30))),
        meeting('h', now.add(const Duration(days: 20)), title: 'Thanksgiving', calendar: 'holidays')];
      expect(await syncCalendar(store, source, on, now: now), 3);
      final read = source.reads.single;
      expect([read.$1, read.$2, read.$3], [now.subtract(calendarWindow), now.add(calendarWindow), {'work', 'holidays'}]);
      final sent = await uploads();
      expect([sent.length, (sent.single['events'] as List).length, sent.single['removed']], [1, 3, isEmpty]);
      expect((sent.single['events'] as List).first, {
        'key': 'work:a:${later(60).millisecondsSinceEpoch}', 'calendar': 'Work', 'title': 'Board meeting',
        'start': later(60).millisecondsSinceEpoch, 'end': later(120).millisecondsSinceEpoch, 'allDay': false,
        'people': [{'name': 'Sam', 'email': 'sam@example.com', 'organizer': true}],
      });
      // Sent again: nothing changed, so nothing goes.
      expect(await syncCalendar(store, source, on, now: later(60)), 0);
      expect((await uploads()).length, 1);
    });

    test('sends a moved, a changed and a deleted event; a moved one is removed at its old start', () async {
      final moved = meeting('m', later(60));
      source.items = [moved, meeting('c', later(180)), meeting('d', later(300))];
      await syncCalendar(store, source, on, now: now);
      await store.done((await store.outbox()).single.id);
      source.items = [meeting('m', later(60 * 25)), meeting('c', later(180), title: 'Board meeting, room 4')];
      expect(await syncCalendar(store, source, on, now: now), 4);
      expect(await keysSent(0, 'events'), ['work:m:${later(60 * 25).millisecondsSinceEpoch}', 'work:c:${later(180).millisecondsSinceEpoch}']);
      expect(await keysSent(0, 'removed'), unorderedEquals([moved.key, 'work:d:${later(300).millisecondsSinceEpoch}']));
      expect((await store.calendarSent()).keys, unorderedEquals([source.items[0].key, source.items[1].key]));
    });

    test('a calendar turned off has its events removed, and is not read', () async {
      final holiday = meeting('h', later(600), calendar: 'holidays');
      source.items = [meeting('a', later(60)), holiday];
      await syncCalendar(store, source, on, now: now);
      expect(await syncCalendar(store, source, on.copyWith(calendarsOff: {'holidays'}), now: now), 1);
      expect([source.reads.last.$3, await keysSent(1, 'events'), await keysSent(1, 'removed')], [{'work'}, isEmpty, [holiday.key]]);
    });

    test('an event that leaves the window\'s past edge is forgotten with no removal', () async {
      final old = meeting('old', now.subtract(const Duration(days: 89)));
      source.items = [old, meeting('a', later(60))];
      await syncCalendar(store, source, on, now: now);
      // Two days later the phone no longer gives the old event: it is before the window.
      source.items = [meeting('a', later(60))];
      expect(await syncCalendar(store, source, on, now: now.add(const Duration(days: 2))), 0);
      expect([(await uploads()).length, (await store.calendarSent()).keys], [1, [source.items.single.key]]);
    });

    test('goes in uploads of up to 200 events, and skips a cancelled event', () async {
      source.items = [for (var i = 0; i < 450; i++) meeting('e$i', later(i)),
        PhoneEvent(calendarId: 'work', eventId: 'x', title: 'Cancelled', start: later(5), end: later(6), cancelled: true)];
      expect(await syncCalendar(store, source, on, now: now), 450);
      expect([for (final upload in await uploads()) (upload['events'] as List).length], [200, 200, 50]);
      expect((await store.calendarSent()).length, 450);
    });

    test('cuts long words, keeps an end before its start at the start, and sends no calendar id', () {
      final body = eventBody(PhoneEvent(calendarId: 'secret-id', eventId: 'e', title: 't' * 600, start: later(10), end: later(5),
        notes: 'n' * 5000, location: '  ', allDay: true, people: [for (var i = 0; i < 120; i++) EventPerson(name: 'P$i')]), 'Home');
      expect([(body['title'] as String).length, (body['notes'] as String).length, body.containsKey('location'), body['end'],
        (body['people'] as List).length, body['allDay'], body['calendar']], [500, 4000, false, later(10).millisecondsSinceEpoch, 100, true, 'Home']);
    });

    test('reads nothing with the calendar off, and a refused calendar removes nothing', () async {
      expect(await syncCalendar(store, source, const Settings(sending: true), now: now), 0);
      expect([source.listed, source.reads], [0, isEmpty]);
      source.items = [meeting('a', later(60))];
      await syncCalendar(store, source, on, now: now);
      source.error = Exception('Calendar access denied');
      await expectLater(syncCalendar(store, source, on, now: now), throwsException);
      expect([(await uploads()).length, (await store.calendarSent()).length], [1, 1]);
    });

    test('turning it off drops waiting uploads and what was sent, so it sends the window again', () async {
      source.items = [meeting('a', later(60))];
      await syncCalendar(store, source, on, now: now);
      expect(await store.waitingEvents(), 1);
      await store.dropCalendar();
      expect([await uploads(), await store.calendarSent()], [isEmpty, isEmpty]);
      expect(await syncCalendar(store, source, on, now: now), 1);
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
      await store.set(healthTypes, askedTypes);
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(60)), isTrue);
      expect([source.reads.length, server.routes.last], [1, 'health']);
      server.answer = (_) => FakeServer.json({}, 503);
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(120)), isFalse);
    });

    test('in webhook mode sends health and points to the webhook with their ids, and no key is needed', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer((_) => http.Response('', 204));
      final source = FakeHealth()..readings = [reading(HealthDataType.STEPS, start, later(5), value: 10)];
      await store.set(settingsKey, const Settings(sending: true, health: true, place: SendPlace.webhook).encode());
      await store.set(healthTypes, askedTypes);
      await store.moveOutbox(ownWebhook);
      await store.addPoint(Pin(at: start, lat: 1, lon: 1, accuracy: 1));
      expect(await backgroundRound(store, connection: null, webhook: hook, health: source,
        sender: Sender(null, null, server.webhook), now: later(60)), isTrue);
      final messages = [for (final request in server.requests) jsonDecode(request.body) as Map];
      expect([for (final message in messages) message['type']], ['health.samples', 'location.points']);
      final sample = (messages[0]['data']['samples'] as List).single as Map;
      final point = (messages[1]['data']['points'] as List).single as Map;
      expect([sample['id'], point['id'], sample['device']['id']], [1, 2, await store.installId()]);
      expect(server.requests.every((request) => request.url.toString() == hook.address), isTrue);
    });

    test('a round from the saved vault, as an iPhone wake runs, sends to the webhook with no key', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final vault = KeyVault(MemoryStorage(), false);
      await vault.saveWebhook(hook);
      final server = FakeServer((_) => http.Response('', 204));
      final source = FakeHealth()..readings = [reading(HealthDataType.STEPS, start, later(5), value: 10)];
      final swift = FakeBackground()..lines = [swiftPoint(start, 43.6, -79.3)];
      await store.set(settingsKey, const Settings(sending: true, health: true, history: true, place: SendPlace.webhook).encode());
      await store.set(healthTypes, askedTypes);
      await store.moveOutbox(ownWebhook);
      expect(await savedRound(store, vault, health: source, sender: Sender(null, null, server.webhook), native: swift,
        places: FakePlaces(), now: later(60)), isTrue);
      expect([swift.drains, source.reads.length], [1, 1]);
      expect([for (final request in server.requests) (request.url.toString(), jsonDecode(request.body)['type'])],
        [(hook.address, 'health.samples'), (hook.address, 'location.points')]);
      expect(await store.waiting(), 0);
    });

    test('in webhook mode sends the calendar as calendar.events, and a switch of place sends its whole window again', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer((_) => http.Response('', 204));
      final calendar = FakeCalendar()..items = [meeting('a', later(60))];
      await store.set(settingsKey, const Settings(sending: true, calendar: true).encode());
      await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), calendar: calendar,
        now: start);
      expect(server.routes, ['calendar']);
      await store.set(settingsKey, const Settings(sending: true, calendar: true, place: SendPlace.webhook).encode());
      await store.moveOutbox(ownWebhook);
      expect(await backgroundRound(store, connection: null, webhook: hook, health: FakeHealth(),
        sender: Sender(null, null, server.webhook), calendar: calendar, now: start), isTrue);
      final message = jsonDecode(server.requests.last.body) as Map;
      expect([message['type'], (message['data']['events'] as List).single['key']],
        ['calendar.events', 'work:a:${later(60).millisecondsSinceEpoch}']);
      expect(server.requests.last.url.toString(), hook.address);
    });

    test('the server gets health and points without the ids the phone keeps for a webhook', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer();
      final source = FakeHealth()..readings = [reading(HealthDataType.STEPS, start, later(5), value: 10)];
      await store.set(settingsKey, const Settings(sending: true, health: true).encode());
      await store.set(healthTypes, askedTypes);
      await store.addPoint(Pin(at: start, lat: 1, lon: 1, accuracy: 1));
      await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(60));
      final rows = [for (final request in server.requests) ...(jsonDecode(request.body) as Map).values.single as List];
      expect([rows.length, rows.any((row) => (row as Map).containsKey('id'))], [2, false]);
    });

    test('sends the calendar\'s changes while it is on, and a calendar it can not read does not fail the round', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer();
      final calendar = FakeCalendar()..items = [meeting('a', later(60))];
      await store.set(settingsKey, const Settings(sending: true).encode());
      await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), calendar: calendar, now: start);
      expect([calendar.listed, server.routes], [0, isEmpty]);
      await store.set(settingsKey, const Settings(sending: true, calendar: true).encode());
      expect(await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), calendar: calendar,
        now: start), isTrue);
      expect(server.routes, ['calendar']);
      expect(jsonDecode(server.requests.single.body)['events'][0]['key'], 'work:a:${later(60).millisecondsSinceEpoch}');
      expect(await store.sentAt(sentCalendar), isNotNull);
      calendar.error = Exception('No calendar in this engine');
      expect(await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), calendar: calendar,
        now: start), isTrue);
    });

    test('on iPhone, moves the points Swift kept into the round, and names only the newest 10', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer();
      final places = FakePlaces();
      final swift = FakeBackground()..lines = [for (var i = 0; i < 12; i++) swiftPoint(later(i), 43.6 + i / 1000, -79.3)];
      await store.set(settingsKey, const Settings(sending: true, history: true).encode());
      expect(await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), native: swift,
        places: places), isTrue);
      final sent = [for (final point in jsonDecode(server.requests.single.body)['points'] as List) point as Map];
      expect([sent.length, sent.first['at'], sent.where((point) => point.containsKey('place')).length], [12, start.millisecondsSinceEpoch, 10]);
      // The two oldest go with no name.
      expect([sent[0]['place'], sent[1]['place'], sent[2]['place']], [null, null, 'Place 10']);
      // History off: Swift's file is not read.
      await store.set(settingsKey, const Settings(sending: true).encode());
      swift.lines = [swiftPoint(later(20), 1, 1)];
      await backgroundRound(store, connection: connection, health: FakeHealth(), sender: Sender(server.api), native: swift, places: places);
      expect(swift.drains, 1);
    });

    test('a Health read refused on a locked iPhone still sends the points, and reads the same span next time', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final server = FakeServer();
      final source = FakeHealth()..error = Exception('Protected health data is inaccessible');
      await store.set(settingsKey, const Settings(sending: true, health: true, history: true).encode());
      await store.set(healthSince, '${start.millisecondsSinceEpoch}');
      await store.addPoint(Pin(at: start, lat: 1, lon: 1, accuracy: 1));
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(60)), isFalse);
      expect([server.routes, await store.get(healthSince)], [['locations'], '${start.millisecondsSinceEpoch}']);
      source.error = null;
      expect(await backgroundRound(store, connection: connection, health: source, sender: Sender(server.api), now: later(120)), isTrue);
      expect(source.reads.last.$1.isBefore(start), isTrue);
    });
  });

  group('the points Swift keeps', () {
    test('are all stored before any name lookup, so a slow or failed lookup loses no point', () async {
      final store = memoryStore();
      addTearDown(store.close);
      final swift = FakeBackground()..lines = [for (var i = 0; i < 12; i++) swiftPoint(later(i), 43.6 + i / 1000, -79.3)];
      final lookup = Completer<String?>();
      var asked = 0;
      Future<String?> name(double lat, double lon) {
        asked++;
        if (asked == 1) return lookup.future;
        if (asked == 2) throw Exception('Too many lookups');
        return Future.value('Place $asked');
      }
      final drained = drainPoints(store, swift, name: name);
      await pumpEventQueue();
      // The first lookup still waits, as one cut off by iOS would, and every point is in the store.
      expect([asked, await store.waitingPoints()], [1, 12]);
      lookup.complete(null);
      expect(await drained, 12);
      await store.queuePoints();
      final points = [for (final item in await store.outbox()) ...item.body['points'] as List];
      final places = {for (final point in points) (point as Map)['at']: point['place']};
      // Newest first: no name, then a failed lookup, then the next 8 named; the 2 oldest are not looked up.
      expect([points.length, asked], [12, 10]);
      expect([places[later(11).millisecondsSinceEpoch], places[later(10).millisecondsSinceEpoch], places[later(9).millisecondsSinceEpoch],
        places[later(0).millisecondsSinceEpoch]], [null, null, 'Place 3', null]);
    });

    test('read as pins, and a line that is not one is skipped', () {
      final pin = pointOf(swiftPoint(start, 43.65, -79.38, accuracy: -1))!;
      expect([pin.at, pin.lat, pin.lon, pin.accuracy], [start, 43.65, -79.38, 0]);
      expect([pointOf('nope'), pointOf('[]'), pointOf('{"at":"x","lat":1,"lon":1,"accuracy":1}')], [null, null, null]);
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
