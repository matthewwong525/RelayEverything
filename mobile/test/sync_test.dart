import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:health/health.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/sync/background.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/location.dart';
import 'package:relay_app/sync/native.dart';
import 'package:relay_app/sync/photos.dart';

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

  group('photos', () {
    late Store store;
    late FakeServer server;
    late FakePhotos photos;
    late FakeNetwork network;

    setUp(() async {
      store = memoryStore();
      server = FakeServer();
      photos = FakePhotos();
      network = FakeNetwork();
      await store.set(settingsKey, const Settings(sending: true, photos: true).encode());
      await store.set(photosSince, '${start.millisecondsSinceEpoch}');
    });
    tearDown(() => store.close());

    Future<bool> round({Connection? key = connection}) => backgroundRound(store, connection: key, health: FakeHealth(),
      sender: Sender(server.api), photos: photos, network: network, now: later(600));

    List<String> queued(List<QueuedPhoto> waiting) => [for (final photo in waiting) photo.assetId];

    test('a photo waiting for Wi-Fi never holds back a note, and goes on Wi-Fi with its time and place, once', () async {
      photos.take('IMG_0001', later(1), lat: 43.65, lon: -79.38);
      await store.addNote(LocalNote(clientId: 'note-0001', text: 'Lunch idea', createdAt: later(2)), send: true);
      network.current = Link.mobile;
      expect(await round(), isTrue);
      expect(server.routes, ['notes']);
      final waiting = (await store.waitingPhotos()).single;
      expect([waiting.assetId, waiting.takenAt, waiting.lat, waiting.lon, waiting.width, waiting.height],
        ['IMG_0001', later(1), 43.65, -79.38, 1600, 1200]);
      expect(waiting.clientId, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      final copy = await store.photoFile(waiting.path);
      expect(copy.readAsBytesSync(), jpegOf(1600, 1200));
      network.current = Link.wifi;
      expect(await round(), isTrue);
      expect(server.routes, ['notes', 'photos']);
      final parts = formParts(server.requests.last);
      expect(parts.keys, ['clientId', 'takenAt', 'lat', 'lon', 'photo']);
      expect([parts['clientId']!.$2, parts['takenAt']!.$2, parts['lat']!.$2, parts['lon']!.$2, parts['photo']!.$1],
        [waiting.clientId, '${later(1).millisecondsSinceEpoch}', '43.65', '-79.38', 'image/jpeg']);
      expect([await store.waitingPhotos(), copy.existsSync()], [isEmpty, false]);
      // The next look starts at the photo's own second and finds it again, but it goes no second time.
      expect(await round(), isTrue);
      expect([server.routes, photos.copied], [['notes', 'photos'], ['IMG_0001']]);
    });

    test('an iPhone wake sends the points Swift kept first, then photos, also when a locked iPhone refuses Health', () async {
      await store.set(settingsKey, const Settings(sending: true, health: true, history: true, photos: true).encode());
      await store.set(healthSince, '${start.millisecondsSinceEpoch}');
      photos.take('IMG_0001', later(1));
      final swift = FakeBackground()..lines = [swiftPoint(later(2), 43.65, -79.38)];
      final health = FakeHealth()..error = Exception('Protected health data is inaccessible');
      // Health is read again next time, so the round is not done; the points and the photo still go.
      expect(await backgroundRound(store, connection: connection, health: health, sender: Sender(server.api), native: swift,
        places: FakePlaces(), photos: photos, network: network, now: later(600)), isFalse);
      expect([server.routes, await store.waitingPhotos()], [['locations', 'photos'], isEmpty]);
    });

    test('with mobile data allowed, photos go on mobile data, and never with no network', () async {
      await store.set(settingsKey, const Settings(sending: true, photos: true, photosOnMobileData: true).encode());
      photos.take('IMG_0001', later(1));
      network.current = Link.none;
      expect(await round(), isTrue);
      expect([server.routes, queued(await store.waitingPhotos())], [isEmpty, ['IMG_0001']]);
      network.current = Link.mobile;
      expect(await round(), isTrue);
      expect([server.routes, await store.waitingPhotos()], [['photos'], isEmpty]);
      expect([photosMayGo(const Settings(sending: true, photos: true), Link.mobile),
        photosMayGo(const Settings(sending: true, photos: true), Link.wifi)], [false, true]);
    });

    test('reads no library and sends no photo while photos or sending is off, or with no key', () async {
      photos.take('IMG_0001', later(1));
      for (final saved in [const Settings(sending: true).encode(), '{"sending":false,"photos":true,"photosOnMobileData":true}']) {
        await store.set(settingsKey, saved);
        expect(await round(), isTrue);
      }
      await store.set(settingsKey, const Settings(sending: true, photos: true).encode());
      expect(await round(key: null), isTrue);
      expect([photos.finds, photos.copied, photos.asked, server.requests, await store.waitingPhotos()],
        [isEmpty, isEmpty, 0, isEmpty, isEmpty]);
    });

    test('queues only photos taken since the switch turned on, 50 a round, oldest first, each once', () async {
      network.current = Link.mobile;
      for (var i = 0; i < 60; i++) {
        photos.take('IMG_${'$i'.padLeft(4, '0')}', later(i + 1));
      }
      // Saved today from an old trip: Android finds it as new, but it was taken before the switch turned on.
      photos.take('old-trip', start.subtract(const Duration(days: 365)), addedAt: later(61));
      expect(await round(), isTrue);
      var waiting = queued(await store.waitingPhotos());
      expect([waiting.length, waiting.first, waiting.last], [50, 'IMG_0000', 'IMG_0049']);
      expect(await store.get(photosAfter), '${later(50).millisecondsSinceEpoch}');
      expect(await round(), isTrue);
      waiting = queued(await store.waitingPhotos());
      expect([waiting.length, waiting.toSet().length, waiting.last], [60, 60, 'IMG_0059']);
      expect(await round(), isTrue);
      expect([(await store.waitingPhotos()).length, photos.copied.length, photos.copied.contains('old-trip')], [60, 60, false]);
      expect([for (final look in photos.finds) look.$1], [start, later(50), later(60)]);
      expect(server.requests, isEmpty);
    });

    test('a photo only in iCloud waits for a network the photo send may use, and so do the photos after it', () async {
      network.current = Link.mobile;
      photos
        ..take('cloud', later(1))
        ..take('local', later(2))
        ..cloudOnly.add('cloud');
      expect(await round(), isTrue);
      expect([await store.waitingPhotos(), photos.copied, await store.get(photosAfter)], [isEmpty, isEmpty, '${start.millisecondsSinceEpoch}']);
      network.current = Link.wifi;
      expect(await round(), isTrue);
      expect([photos.copied, server.routes], [['cloud', 'local'], ['photos', 'photos']]);
    });

    test('a photo the server turns down is dropped with its copy; an offline answer stops only the photo send', () async {
      network.current = Link.mobile;
      photos
        ..take('refused', later(1))
        ..take('waits', later(2));
      expect(await round(), isTrue);
      final files = [for (final photo in await store.waitingPhotos()) await store.photoFile(photo.path)];
      network.current = Link.wifi;
      var tries = 0;
      server.answer = (request) => !request.url.path.endsWith('photos') ? FakeServer.ok(request)
        : tries++ == 0 ? FakeServer.json({'error': 'not a JPEG'}, 400) : FakeServer.json({}, 503);
      await store.addNote(LocalNote(clientId: 'note-0001', text: 'Lunch idea', createdAt: later(3)), send: true);
      expect(await round(), isFalse);
      expect(server.routes, ['notes', 'photos', 'photos']);
      expect([queued(await store.waitingPhotos()), files.first.existsSync(), files.last.existsSync()], [['waits'], false, true]);
      server.answer = FakeServer.ok;
      expect(await round(), isTrue);
      expect([await store.waitingPhotos(), files.last.existsSync()], [isEmpty, false]);
    });

    test('a photo the phone can not copy small enough is skipped, once', () async {
      photos
        ..take('broken', later(1))
        ..take('huge', later(2))
        ..take('fine', later(3))
        ..jpegs['broken'] = null
        ..jpegs['huge'] = jpegOf(2000, 1500);
      expect(await round(), isTrue);
      expect(await round(), isTrue);
      expect([photos.copied, server.routes, await store.waitingPhotos()], [['broken', 'huge', 'fine'], ['photos'], isEmpty]);
    });

    test('a photo the phone fails to copy once waits, with the photos after it, and goes on the next round, once', () async {
      network.current = Link.mobile;
      var failures = 0;
      photos
        ..take('first', later(1))
        ..take('fails', later(2))
        ..take('third', later(3))
        ..whileCopying = (photo) async {
          if (photo.id == 'fails' && failures++ == 0) throw Exception('iCloud download failed');
        };
      expect(await round(), isTrue);
      expect([queued(await store.waitingPhotos()), photos.copied, await store.get(photosFailed)],
        [['first'], ['first', 'fails'], '{"fails":1}']);
      expect(await round(), isTrue);
      expect(await round(), isTrue);
      expect([queued(await store.waitingPhotos()), photos.copied, await store.get(photosFailed)],
        [['first', 'fails', 'third'], ['first', 'fails', 'fails', 'third'], '{}']);
      // The phone ends the round at the next photo after one is queued: that one is not queued again.
      photos
        ..take('fourth', later(4))
        ..take('fifth', later(5));
      var asks = 0;
      await expectLater(queuePhotos(store, photos, network: false, keepGoing: () async {
        if (asks++ == 2) throw Exception('task ended');
        return true;
      }), throwsException);
      expect(queued(await store.waitingPhotos()), ['first', 'fails', 'third', 'fourth']);
      expect(await round(), isTrue);
      expect(queued(await store.waitingPhotos()), ['first', 'fails', 'third', 'fourth', 'fifth']);
      expect(photos.copied, ['first', 'fails', 'fails', 'third', 'fourth', 'fifth']);
    });

    test('a photo whose copy always fails is skipped after 3 rounds, and the photos after it then go', () async {
      network.current = Link.mobile;
      photos
        ..take('broken', later(1))
        ..take('next', later(2))
        ..whileCopying = (photo) async {
          if (photo.id == 'broken') throw Exception('iCloud download failed');
        };
      expect(await round(), isTrue);
      expect(await round(), isTrue);
      expect([await store.waitingPhotos(), photos.copied, await store.get(photosFailed)],
        [isEmpty, ['broken', 'broken'], '{"broken":2}']);
      expect(await round(), isTrue);
      expect([queued(await store.waitingPhotos()), photos.copied, await store.get(photosFailed)],
        [['next'], ['broken', 'broken', 'broken', 'next'], '{}']);
      expect(await round(), isTrue);
      expect([queued(await store.waitingPhotos()), photos.copied.length], [['next'], 4]);
    });

    test('photos turned off in the app while a copy is made keep no photo and no copy on the phone', () async {
      network.current = Link.mobile;
      photos
        ..take('IMG_0001', later(1))
        ..take('IMG_0002', later(2))
        ..whileCopying = (_) async {
          // The app turns photos off and drops the queue, while this background round makes its copy.
          await store.set(settingsKey, const Settings(sending: true).encode());
          await dropPhotoQueue(store);
        };
      expect(await round(), isTrue);
      final copies = Directory((await store.photoFile('photos')).path);
      expect([await store.waitingPhotos(), photos.copied, copies.listSync()], [isEmpty, ['IMG_0001'], isEmpty]);
    });

    test('a refused photo with a key that answers, as on an older server, stops only the photo send', () async {
      photos.take('IMG_0001', later(1));
      server.answer = (request) => request.url.path.endsWith('photos') ? FakeServer.json({}, 403) : FakeServer.ok(request);
      expect(await round(), isTrue);
      expect([server.routes, queued(await store.waitingPhotos())], [['photos', 'key'], ['IMG_0001']]);
    });

    test('a turned-off key with only photos waiting fails the round, as for the notes, and keeps the photos', () async {
      photos.take('IMG_0001', later(1));
      server.answer = (_) => FakeServer.json({}, 403);
      expect(await round(), isFalse);
      expect([server.routes, queued(await store.waitingPhotos())], [['photos', 'key'], ['IMG_0001']]);
    });

    test('turning off drops the waiting photos and their copies, and forgets where the library was read to', () async {
      network.current = Link.mobile;
      photos.take('IMG_0001', later(1));
      expect(await round(), isTrue);
      final copy = await store.photoFile((await store.waitingPhotos()).single.path);
      await dropPhotoQueue(store);
      expect([await store.waitingPhotos(), copy.existsSync()], [isEmpty, false]);
      expect([await store.get(photosSince), await store.get(photosAfter), await store.get(photosSeen), await store.get(photosFailed)],
        [null, null, null, null]);
      // With no start time, a round queues nothing, even with photos on.
      expect(await round(), isTrue);
      expect(await store.waitingPhotos(), isEmpty);
    });

    test('reads a JPEG\'s own size, and finds none in what is not one', () {
      expect([jpegSize(jpegOf(1600, 1200)), jpegSize(jpegOf(900, 1600))], [(1600, 1200), (900, 1600)]);
      expect(jpegSize([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), isNull);
      expect(jpegSize([0xFF, 0xD8, 0xFF, 0xD9]), isNull);
      expect(jpegSize(jpegOf(1600, 1200).sublist(0, 25)), isNull);
    });

    test('fits a photo to 1,600 px on its long side, keeps its place only when it has one, and names it by a UUID', () {
      expect([fitBox(4032, 3024), fitBox(3024, 4032), fitBox(800, 600), fitBox(4000, 1)], [(1600, 1200), (1200, 1600), (800, 600), (1600, 1)]);
      expect(photoPlace(43.65, -79.38), (43.65, -79.38));
      for (final (lat, lon) in [(0.0, 0.0), (null, 1.0), (1.0, null), (91.0, 0.0), (0.0, 181.0), (double.nan, 1.0)]) {
        expect(photoPlace(lat, lon), isNull, reason: '$lat, $lon');
      }
      final id = newPhotoId(Random(1));
      expect(id, matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(id, matches(RegExp(r'^[A-Za-z0-9-]{8,64}$')));
      expect(newPhotoId(), isNot(newPhotoId()));
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
