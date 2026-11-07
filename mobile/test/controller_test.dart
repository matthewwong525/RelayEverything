import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/photos.dart';
import 'package:relay_app/voice/model.dart';

import 'fakes.dart';

final now = DateTime.fromMillisecondsSinceEpoch(1793797200000);

void main() {
  late Store store;
  late MemoryStorage storage;
  late FakeServer server;
  late FakePlaces places;
  late FakeHealth health;
  late List<bool> scheduled;
  var clock = now;

  RelayController controller() => RelayController(store: store, vault: KeyVault(storage), places: places, health: health,
    apiFor: server.api, clock: () => clock, schedule: (on) async => scheduled.add(on));

  List<Map<String, dynamic>> sentNotes() => [
    for (final request in server.requests) if (request.url.path.endsWith('notes')) jsonDecode(request.body) as Map<String, dynamic>,
  ];

  setUp(() {
    store = memoryStore();
    storage = MemoryStorage();
    server = FakeServer();
    places = FakePlaces();
    health = FakeHealth();
    scheduled = [];
    clock = now;
  });
  tearDown(() => store.close());

  group('with sending off', () {
    test('a new install keeps notes and pins on this phone, and calls no server and no place lookup', () async {
      server = noNetwork();
      places.pin = Pin(at: now, lat: 43.64871, lon: -79.38171, accuracy: 12);
      final relay = controller();
      await relay.load();
      expect([relay.connected, relay.settings.sending, relay.settings.pinNotes], [false, false, false]);
      await relay.addNote('Bare');
      expect(await relay.setPinNotes(true), isNull);
      clock = now.add(const Duration(minutes: 1));
      await relay.addNote('Pinned one');
      await pumpEventQueue();
      expect([for (final entry in relay.entries) (entry.text, entry.place, entry.waiting)],
        [('Pinned one', 'Pinned', false), ('Bare', null, false)]);
      expect(places.named, [false]);
      await relay.sync();
      expect([relay.status, relay.waiting], [SyncStatus.idle, 0]);
      expect(await store.outbox(), isEmpty);
      expect(await relay.earlierNotes(), 2);
      expect(await relay.setHealth(true), contains('Send to Relay Everything'));
      expect(await relay.setHistory(true), contains('Send to Relay Everything'));
      expect([places.asked, health.reads, scheduled], [[false], isEmpty, [false]]);
      expect(server.requests, isEmpty);
    });

    test('a key kept with sending off sends nothing, and turning on with no key is refused', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.startSending(sendEarlier: true), 'Connect a key first.');
      expect(relay.settings.sending, isFalse);
      server.answer = FakeServer.ok;
      expect(await relay.connect(code), isNull);
      final checked = server.requests.length;
      expect([relay.connected, relay.settings.sending, server.routes], [true, false, ['key']]);
      await relay.addNote('Still local');
      await relay.sync();
      expect([server.requests.length, (await store.outbox()).length], [checked, 0]);
    });
  });

  group('turning sending on', () {
    Future<RelayController> offlineWithNotes(List<String> texts) async {
      final relay = controller();
      await relay.load();
      for (final (index, text) in texts.indexed) {
        clock = now.add(Duration(minutes: index));
        await relay.addNote(text);
      }
      await pumpEventQueue();
      expect(await relay.connect(code), isNull);
      return relay;
    }

    test('only new notes: the earlier ones stay, and the next turn-on asks about them again', () async {
      final relay = await offlineWithNotes(['One', 'Two', 'Three']);
      expect(await relay.earlierNotes(), 3);
      expect(await relay.startSending(sendEarlier: false), isNull);
      await pumpEventQueue();
      expect(sentNotes(), isEmpty);
      clock = now.add(const Duration(hours: 1));
      await relay.addNote('New');
      await pumpEventQueue();
      expect([for (final note in sentNotes()) note['text']], ['New']);
      await relay.stopSending();
      await relay.addNote('Off again');
      expect(await relay.earlierNotes(), 4);
      expect(await relay.startSending(sendEarlier: true), isNull);
      await pumpEventQueue();
      expect([for (final note in sentNotes()) note['text']], ['New', 'One', 'Two', 'Three', 'Off again']);
      expect(await relay.earlierNotes(), 0);
      expect(storage.values.values, contains('secret-value'));
    });

    test('a pinned note written while on gets its place name from the phone, as in the first version', () async {
      final relay = await offlineWithNotes([]);
      await relay.setPinNotes(true);
      await relay.startSending(sendEarlier: false);
      await pumpEventQueue();
      places.pin = Pin(at: now, lat: 43.65, lon: -79.4, accuracy: 8, place: 'Ossington Ave');
      await relay.addNote('Named');
      await pumpEventQueue();
      expect(places.named, [true]);
      expect(sentNotes().single['place'], 'Ossington Ave');
    });

    test('the list shows only the notes made on this phone, each sent or not, and reads nothing from the server', () async {
      final relay = await offlineWithNotes(['Local only']);
      await relay.startSending(sendEarlier: false);
      await pumpEventQueue();
      clock = now.add(const Duration(hours: 1));
      await relay.addNote('Sent');
      await pumpEventQueue();
      await relay.sync();
      expect([for (final entry in relay.entries) (entry.text, entry.sent, entry.waiting)],
        [('Sent', true, false), ('Local only', false, false)]);
      expect(server.routes, ['key', 'notes']);
      await relay.stopSending();
      expect(relay.entries, hasLength(2));
    });
  });

  group('turning sending off', () {
    test('drops waiting health and location, stops reading them, and keeps notes, their uploads and the key', () async {
      await KeyVault(storage).save(connection);
      server.answer = (_) => FakeServer.json({}, 503);
      final relay = controller();
      await relay.load();
      expect(await relay.setHistory(true), isNull);
      expect(await relay.setHealth(true), isNull);
      await pumpEventQueue();
      health.readings = [reading(HealthDataType.STEPS, now, now.add(const Duration(minutes: 5)), value: 10)];
      await relay.sync();
      places.points.add(Pin(at: now, lat: 43.6, lon: -79.3, accuracy: 9));
      await pumpEventQueue();
      await relay.setPinNotes(false);
      await relay.addNote('Waits');
      await pumpEventQueue();
      expect(places.points.hasListener, isTrue);
      expect([for (final item in await store.outbox()) item.route], containsAll(['health', 'notes']));
      await relay.stopSending();
      expect([relay.settings.sending, relay.settings.health, relay.settings.history, places.points.hasListener], [false, false, false, false]);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      await store.queuePoints();
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      expect([scheduled.last, relay.connected, relay.entries.single.text], [false, true, 'Waits']);
      final reads = health.reads.length;
      server.requests.clear();
      await relay.sync();
      expect([health.reads.length, server.requests], [reads, isEmpty]);
      // Back on: the note's upload goes with no second prompt, and health and history stay off until turned on.
      expect(await relay.earlierNotes(), 0);
      server.answer = FakeServer.ok;
      await relay.startSending(sendEarlier: false);
      await pumpEventQueue();
      expect([sentNotes().single['text'], relay.settings.health, relay.settings.history], ['Waits', false, false]);
    });

    test('a round already sending when sending stops sends, reads and queues nothing more', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      await relay.setPinNotes(false);
      expect(await relay.setHistory(true), isNull);
      expect(await relay.setHealth(true), isNull);
      await pumpEventQueue();
      health.readings = [reading(HealthDataType.STEPS, now, now.add(const Duration(minutes: 5)), value: 10)];
      places.points.add(Pin(at: now, lat: 43.6, lon: -79.3, accuracy: 9));
      await pumpEventQueue();
      server.requests.clear();
      server.hold = Completer();
      await relay.addNote('First');
      await relay.addNote('Second');
      await pumpEventQueue();
      // The round has read health, queued the location point, and holds open its first upload.
      expect(server.routes, ['notes']);
      expect([for (final item in await store.outbox()) item.route], containsAll(['notes', 'health', 'locations']));
      final reads = health.reads.length;
      final stopped = relay.stopSending();
      await pumpEventQueue();
      server.hold!.complete();
      await stopped;
      await pumpEventQueue();
      expect([server.routes, health.reads.length, relay.status], [['notes'], reads, SyncStatus.idle]);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
    });

    test('health starts from the moment it turns on, with no earlier backfill', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      expect(await relay.setHealth(true), isNull);
      await pumpEventQueue();
      expect(health.reads.first.$2, now);
      expect(health.reads.first.$1, now.subtract(const Duration(hours: 2)));
      expect(await store.get(healthSince), '${now.millisecondsSinceEpoch}');
    });
  });

  group('settings', () {
    test('start off on a new install; sending off forces health and history off', () {
      const fresh = Settings();
      expect([fresh.sending, fresh.pinNotes, fresh.history, fresh.health], [false, false, false, false]);
      expect([const Settings(history: true, health: true).history, const Settings(history: true, health: true).health], [false, false]);
      const on = Settings(sending: true, history: true, health: true);
      expect([on.copyWith(sending: false).history, on.copyWith(sending: false).health], [false, false]);
      expect(jsonDecode(on.encode()),
        {'sending': true, 'pinNotes': false, 'history': true, 'health': true, 'photos': false, 'photosOnMobileData': false});
      final back = Settings.decode(on.encode(), hasKey: false);
      expect([back.sending, back.health], [true, true]);
    });

    test('photos are off unless sending is on, and mobile data is off unless photos is on', () {
      const fresh = Settings();
      expect([fresh.photos, fresh.photosOnMobileData], [false, false]);
      expect([const Settings(photos: true).photos, const Settings(sending: true, photosOnMobileData: true).photosOnMobileData], [false, false]);
      const on = Settings(sending: true, photos: true, photosOnMobileData: true);
      expect([on.photos, on.photosOnMobileData], [true, true]);
      expect([on.copyWith(sending: false).photos, on.copyWith(sending: false).photosOnMobileData], [false, false]);
      expect([on.copyWith(photos: false).photosOnMobileData, on.copyWith(photosOnMobileData: false).photos], [false, true]);
      final back = Settings.decode(on.encode(), hasKey: true);
      expect([back.photos, back.photosOnMobileData], [true, true]);
      // Settings saved before photos have none of their fields: photos read as off.
      final old = Settings.decode(jsonEncode({'sending': true, 'pinNotes': true, 'history': true, 'health': true}), hasKey: true);
      expect([old.sending, old.history, old.health, old.photos, old.photosOnMobileData], [true, true, true, false, false]);
      expect(Settings.decode(jsonEncode({'pinNotes': true}), hasKey: true).photos, isFalse);
    });

    test('an upgrade from the first version keeps sending on for a phone with a key', () {
      final kept = Settings.decode(null, hasKey: true);
      expect([kept.sending, kept.pinNotes, kept.history], [true, true, false]);
      final saved = jsonEncode({'pinNotes': false, 'history': true, 'health': true});
      final upgraded = Settings.decode(saved, hasKey: true);
      expect([upgraded.sending, upgraded.pinNotes, upgraded.history, upgraded.health], [true, false, true, true]);
      final noKey = Settings.decode(saved, hasKey: false);
      expect([noKey.sending, noKey.history, noKey.health], [false, false, false]);
      expect(Settings.decode(null, hasKey: false).sending, isFalse);
    });

    test('are saved in the new shape on load, and sending reads as off with no key', () async {
      await store.set('settings', jsonEncode({'sending': true, 'pinNotes': true, 'history': true, 'health': false}));
      final relay = controller();
      await relay.load();
      expect([relay.settings.sending, relay.settings.pinNotes], [false, true]);
      expect(jsonDecode((await store.get('settings'))!),
        {'sending': false, 'pinNotes': true, 'history': false, 'health': false, 'photos': false, 'photosOnMobileData': false});
    });

    test('turn each on only with its permission, and schedule the hourly sync only while sending', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings().encode());
      final relay = controller();
      await relay.load();
      places.allowed = false;
      health.allowed = false;
      expect(await relay.setPinNotes(true), contains('location'));
      expect(await relay.startSending(sendEarlier: false), isNull);
      expect(await relay.setHistory(true), contains('all the time'));
      expect(await relay.setHealth(true), contains('health'));
      expect([relay.settings.history, relay.settings.health], [false, false]);
      places.allowed = true;
      health.allowed = true;
      expect(await relay.setHistory(true), isNull);
      expect(await relay.setHealth(true), isNull);
      expect(await relay.setHistory(false), isNull);
      expect(await relay.setPinNotes(true), isNull);
      expect(scheduled, [false, true, true, true, true]);
      expect(jsonDecode((await store.get('settings'))!),
        {'sending': true, 'pinNotes': true, 'history': false, 'health': true, 'photos': false, 'photosOnMobileData': false});
      expect(places.asked, [false, true, true, false]);
    });
  });

  group('with sending on', () {
    test('connects with a key the server takes, checked by GET key, and syncs once sending is on', () async {
      final relay = controller();
      await relay.load();
      expect(relay.connected, isFalse);
      expect(await relay.connect('nonsense'), contains('not a Relay Everything key'));
      expect(await relay.connect(code), isNull);
      expect([server.requests.single.method, server.routes], ['GET', ['key']]);
      expect(await relay.startSending(sendEarlier: false), isNull);
      await relay.addNote('Lunch idea');
      await pumpEventQueue();
      await relay.sync();
      expect(relay.connected, isTrue);
      expect(relay.server, 'https://relay.example.com');
      expect(storage.values.values, contains('secret-value'));
      expect(relay.status, SyncStatus.synced);
      expect([relay.entries.single.text, relay.entries.single.sent], ['Lunch idea', true]);
      // A device key only adds: the one read is the key check.
      expect([for (final request in server.requests) if (request.method == 'GET') request.url.path.split('/').last], ['key']);
    });

    test('connects with a key from the Relay Everything page, and sends it as Authorization: Bearer', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      expect(storage.values['relay.key'], pageKey);
      await relay.startSending(sendEarlier: false);
      await relay.addNote('From a page key');
      await pumpEventQueue();
      await relay.sync();
      expect(server.routes, ['key', 'notes']);
      expect([for (final request in server.requests) request.headers['Authorization']], ['Bearer $pageKey', 'Bearer $pageKey']);
      expect([for (final request in server.requests) request.headers['CF-Access-Client-Id']], [null, null]);
    });

    test('refuses a key the server turns down, and keeps one it could not try', () async {
      final relay = controller();
      for (final status in [401, 403]) {
        server.answer = (_) => FakeServer.json({}, status);
        expect(await relay.connect(code), contains('did not take this key'), reason: '$status');
        expect(relay.connected, isFalse);
      }
      server.answer = (_) => FakeServer.json({}, 503);
      expect(await relay.connect(code), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.addNote('Waits');
      await pumpEventQueue();
      await relay.sync();
      expect([relay.connected, relay.status], [true, SyncStatus.offline]);
    });

    test('shows a note at once as waiting, with its pin, and sent after the next sync', () async {
      await KeyVault(storage).save(connection);
      places.pin = Pin(at: now, lat: 43.64871, lon: -79.38171, accuracy: 12);
      server.answer = (_) => FakeServer.json({}, 503);
      final relay = controller();
      await relay.load();
      await relay.addNote('  Lunch idea  ');
      await pumpEventQueue();
      await relay.sync();
      expect([relay.entries.single.text, relay.entries.single.waiting, relay.entries.single.place], ['Lunch idea', true, 'Pinned']);
      expect([relay.status, relay.waiting], [SyncStatus.offline, 1]);
      server.answer = FakeServer.ok;
      await relay.sync();
      expect([for (final entry in relay.entries) (entry.text, entry.waiting, entry.sent)], [('Lunch idea', false, true)]);
      expect([relay.waiting, relay.status], [0, SyncStatus.synced]);
      // The two tries with no signal reached the notes route too; the last one landed.
      final sent = sentNotes().last;
      expect(sent, containsPair('createdAt', 1793797200000));
      expect(sent['clientId'], matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('keeps a note at once, and adds its pin when the phone has a fix', () async {
      await KeyVault(storage).save(connection);
      server.answer = (_) => FakeServer.json({}, 503);
      places.fix = Completer();
      final relay = controller();
      await relay.load();
      await relay.addNote('Bench idea');
      expect([relay.entries.single.text, relay.entries.single.place, relay.waiting], ['Bench idea', null, 1]);
      places.fix!.complete(Pin(at: now, lat: 43.64871, lon: -79.38171, accuracy: 12, place: 'Queen St W'));
      await pumpEventQueue();
      expect(relay.entries.single.place, 'Queen St W');
      final sent = sentNotes().single;
      expect([sent['text'], sent['lat'], sent['place']], ['Bench idea', 43.64871, 'Queen St W']);
      // A note not waiting, such as one settled already, keeps no late pin.
      expect(await store.settlePin('gone', Pin(at: now, lat: 1, lon: 1, accuracy: 1), send: true), isFalse);
    });

    test('a second note syncs while the first waits for its pin, and the first goes later with its place', () async {
      await KeyVault(storage).save(connection);
      final first = Completer<Pin?>();
      places.fix = first;
      final relay = controller();
      await relay.load();
      await relay.addNote('First');
      await pumpEventQueue();
      places
        ..fix = null
        ..pin = Pin(at: now, lat: 43.65, lon: -79.40, accuracy: 8, place: 'Ossington Ave');
      await relay.addNote('Second');
      await pumpEventQueue();
      await relay.sync(); // pull to refresh, the sync chip or the app's return
      expect([for (final note in sentNotes()) note['text']], ['Second']);
      expect(sentNotes().single['place'], 'Ossington Ave');
      expect([relay.waiting, for (final entry in relay.entries) if (entry.waiting) entry.text], [1, 'First']);
      first.complete(Pin(at: now, lat: 43.64871, lon: -79.38171, accuracy: 12, place: 'Queen St W'));
      await pumpEventQueue();
      await relay.sync();
      expect([for (final note in sentNotes()) note['text']], ['Second', 'First']);
      expect([sentNotes().last['lat'], sentNotes().last['place']], [43.64871, 'Queen St W']);
      expect(relay.waiting, 0);
    });

    test('a note goes without a place when the phone gives up, or when the app closed while it waited', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      await relay.addNote('No fix');
      await pumpEventQueue();
      await relay.sync();
      expect(sentNotes().single, isNot(contains('lat')));
      await store.addNote(LocalNote(clientId: 'closed', text: 'Cut short', createdAt: now), waitForPin: true, send: true);
      expect([(await store.outbox()).length, await store.waiting()], [0, 1]);
      await controller().load();
      expect((await store.outbox()).single.body, {'clientId': 'closed', 'text': 'Cut short', 'createdAt': now.millisecondsSinceEpoch});
    });

    test('opens with its notes and settings, with no network, and deletes the timeline the first versions kept', () async {
      await KeyVault(storage).save(connection);
      await store.set('timeline', jsonEncode([{'id': 'a', 'source': 'ring', 'text': 'Call the PCB fab', 'recordedAt': 1793797100000}]));
      await store.set('settings', jsonEncode({'pinNotes': false, 'history': true, 'health': true}));
      final relay = controller();
      await relay.load();
      expect([relay.entries, await store.get('timeline')], [isEmpty, isNull]);
      expect([relay.settings.sending, relay.settings.pinNotes, relay.settings.history, relay.settings.health], [true, false, true, true]);
      places.points.add(Pin(at: now, lat: 43.6, lon: -79.3, accuracy: 9));
      await pumpEventQueue();
      await relay.addNote('No pin');
      await relay.sync();
      expect(server.routes, containsAll(['notes', 'locations']));
      expect(server.routes, isNot(contains('timeline')));
      expect(sentNotes().single, isNot(contains('lat')));
      expect(relay.entries.single.text, 'No pin');
      relay.dispose();
    });

    test('sends health on each sync, and goes on when the health store is closed', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', jsonEncode({'pinNotes': true, 'history': false, 'health': true}));
      final relay = controller();
      await relay.load();
      health.readings = [reading(HealthDataType.STEPS, now.subtract(const Duration(hours: 1)), now, value: 100)];
      await relay.sync();
      expect(server.routes.first, 'health');
      health.error = Exception('locked');
      await relay.sync();
      expect(relay.status, SyncStatus.synced);
    });

    test('says when the key is refused, or the server can not be reached', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      await relay.sync();
      expect(relay.status, SyncStatus.synced);
      server.answer = (_) => FakeServer.json({}, 401);
      await relay.addNote('x');
      await pumpEventQueue();
      await relay.sync();
      expect(relay.status, SyncStatus.refused);
      server.answer = (_) => FakeServer.json({}, 502);
      await relay.sync();
      expect(relay.status, SyncStatus.offline);
      server.answer = FakeServer.ok;
      await relay.sync();
      expect([relay.status, relay.waiting], [SyncStatus.synced, 0]);
    });

    test('changes the server, and disconnects: the key goes, sending turns off, notes stay', () async {
      final relay = controller();
      expect(await relay.setServer('https://preview.example.com'), 'Connect a key first.');
      await KeyVault(storage).save(connection);
      await relay.load();
      expect(await relay.setServer('preview.example.com'), contains('https://'));
      expect(await relay.setServer('https://preview.example.com/'), isNull);
      expect(relay.server, 'https://preview.example.com');
      server.answer = (_) => FakeServer.json({}, 503);
      await relay.addNote('Kept');
      await relay.disconnect();
      expect([relay.connected, relay.settings.sending, relay.status], [false, false, SyncStatus.idle]);
      expect(storage.values, isEmpty);
      expect(relay.entries.single.text, 'Kept');
      await relay.sync();
      expect(server.requests.every((request) => request.url.host == 'preview.example.com'), isTrue);
    });
  });

  group('photos', () {
    late FakePhotos photos;
    late FakeNetwork network;
    setUp(() {
      photos = FakePhotos();
      network = FakeNetwork();
    });

    RelayController photoController() => RelayController(store: store, vault: KeyVault(storage), places: places, health: health,
      apiFor: server.api, clock: () => clock, schedule: (on) async => scheduled.add(on), photos: photos, network: network);

    Future<RelayController> sending() async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true).encode());
      final relay = photoController();
      await relay.load();
      return relay;
    }

    List<String> photoUploads() => [for (final route in server.routes) if (route == 'photos') route];
    final later = now.add(const Duration(minutes: 1));

    test('never turned on: the app asks for no photo access and reads no library', () async {
      final relay = await sending();
      photos.take('IMG_0001', later);
      await relay.addNote('Lunch idea');
      await relay.sync();
      expect([photos.asked, photos.finds, photoUploads(), sentNotes().single['text']], [0, isEmpty, isEmpty, 'Lunch idea']);
      expect(await relay.setPhotosOnMobileData(true), contains('Photos'));
      expect(relay.settings.photosOnMobileData, isFalse);
    });

    test('turns on only with sending and photo access, and sends only photos taken from then on', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings().encode());
      final relay = photoController();
      await relay.load();
      expect(await relay.setPhotos(true), contains('Send to Relay Everything'));
      expect(photos.asked, 0);
      await relay.startSending(sendEarlier: false);
      photos.allowed = false;
      expect(await relay.setPhotos(true), "Photo access is off. Turn it on in the phone's Settings.");
      expect([relay.settings.photos, await store.get(photosSince), photos.asked], [false, null, 1]);
      photos
        ..allowed = true
        ..take('before', now.subtract(const Duration(days: 30)));
      expect(await relay.setPhotos(true), isNull);
      expect([relay.settings.photos, await store.get(photosSince), await store.get(photosAfter)],
        [true, '${now.millisecondsSinceEpoch}', '${now.millisecondsSinceEpoch}']);
      // The hourly round runs while photos alone are on.
      expect(scheduled.last, isTrue);
      await relay.sync();
      expect([photos.copied, photoUploads()], [isEmpty, isEmpty]);
      // A photo taken after: the next sync, on open or on a return to the app, sends it.
      clock = now.add(const Duration(minutes: 5));
      photos.take('after', later, lat: 43.65, lon: -79.38);
      await relay.sync();
      expect([photos.copied, photoUploads(), relay.status], [['after'], ['photos'], SyncStatus.synced]);
      expect(jsonDecode((await store.get('settings'))!), containsPair('photos', true));
    });

    test('on mobile data, photos wait for Wi-Fi while notes go, and go once mobile data is allowed', () async {
      final relay = await sending();
      network.current = Link.mobile;
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      await relay.addNote('Lunch idea');
      await relay.sync();
      expect([sentNotes().single['text'], photoUploads(), (await store.waitingPhotos()).length], ['Lunch idea', isEmpty, 1]);
      expect(await relay.setPhotosOnMobileData(true), isNull);
      await relay.sync();
      expect([relay.settings.photosOnMobileData, photoUploads(), await store.waitingPhotos()], [true, ['photos'], isEmpty]);
    });

    test('turning photos off drops the photos waiting and their copies, and a later turn-on starts again from then', () async {
      final relay = await sending();
      network.current = Link.mobile;
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      await relay.sync();
      final copy = await store.photoFile((await store.waitingPhotos()).single.path);
      expect(copy.existsSync(), isTrue);
      expect(await relay.setPhotos(false), isNull);
      expect([relay.settings.photos, relay.settings.photosOnMobileData, await store.waitingPhotos(), copy.existsSync()],
        [false, false, isEmpty, false]);
      expect([await store.get(photosSince), await store.get(photosAfter), scheduled.last], [null, null, false]);
      final looks = photos.finds.length;
      network.current = Link.wifi;
      await relay.sync();
      expect([photos.finds.length, photoUploads()], [looks, isEmpty]);
      // On again: the photo was taken before this turn-on, so it never goes.
      clock = now.add(const Duration(minutes: 10));
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      expect([photoUploads(), await store.get(photosSince), photos.asked], [isEmpty, '${clock.millisecondsSinceEpoch}', 2]);
    });

    test('a server that refuses photos stops only the photo send: notes go and the key shows no refusal', () async {
      final relay = await sending();
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      // An older server: the phone's key may send notes, but not photos.
      server.answer = (request) => request.url.path.endsWith('photos') ? FakeServer.json({}, 403) : FakeServer.ok(request);
      await relay.addNote('Lunch idea');
      await relay.sync();
      expect([sentNotes().single['text'], photoUploads(), (await store.waitingPhotos()).length, relay.status],
        ['Lunch idea', ['photos'], 1, SyncStatus.synced]);
      // The phone asks about its key, which answers: the server only has no photos.
      expect(server.routes.last, 'key');
      server.answer = (request) => request.url.path.endsWith('photos') ? FakeServer.json({}, 403) : FakeServer.json({}, 502);
      await relay.addNote('Waits');
      await relay.sync();
      expect(relay.status, SyncStatus.offline);
    });

    test('a turned-off key shows refused when only photos are waiting', () async {
      final relay = await sending();
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      expect(relay.status, SyncStatus.synced);
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      server.answer = (_) => FakeServer.json({}, 403);
      await relay.sync();
      expect([sentNotes(), server.routes.sublist(server.routes.length - 2), (await store.waitingPhotos()).length, relay.status],
        [isEmpty, ['photos', 'key'], 1, SyncStatus.refused]);
    });

    test('stopping sending drops the photos waiting, stops reading the library, and keeps notes and their uploads', () async {
      final relay = await sending();
      network.current = Link.mobile;
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      server.answer = (_) => FakeServer.json({}, 503);
      await relay.addNote('Waits');
      await relay.sync();
      expect([relay.status, (await store.waitingPhotos()).length], [SyncStatus.offline, 1]);
      await relay.stopSending();
      expect([relay.settings.photos, await store.waitingPhotos(), await store.get(photosSince)], [false, isEmpty, null]);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      final looks = photos.finds.length;
      await relay.startSending(sendEarlier: false);
      await relay.sync();
      expect([relay.settings.photos, photos.finds.length], [false, looks]);
    });
  });

  group('voice notes', () {
    late Directory folder;
    late ModelServer models;
    late FakeMicrophone microphone;
    late FakeTranscriber transcriber;
    late FakePlayer player;
    late List<String> notices;

    setUp(() async {
      folder = tempFolder();
      models = ModelServer();
      microphone = FakeMicrophone();
      transcriber = FakeTranscriber();
      player = FakePlayer();
      notices = [];
      await placeModel(folder);
    });

    RelayController voiceController() {
      final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
        clock: () => clock, schedule: (on) async => scheduled.add(on),
        voice: fakeVoice(folder, models, clock: () => clock, microphone: microphone, transcriber: transcriber, player: player));
      relay.notices.listen(notices.add);
      return relay;
    }

    /// Holds the button for [length], then lets go.
    Future<String?> hold(RelayController relay, Duration length) async {
      expect(await relay.startVoiceNote(), isNull);
      expect(relay.listening, clock);
      clock = clock.add(length);
      return relay.endVoiceNote();
    }

    List<String> recordings() => [
      if (Directory('${folder.path}/voice').existsSync())
        for (final file in Directory('${folder.path}/voice').listSync()) file.uri.pathSegments.last,
    ];

    test('in airplane mode: the note shows at once, its words fill in, and no request leaves the phone', () async {
      server = noNetwork();
      final relay = voiceController();
      await relay.load();
      expect(relay.speechModel, ModelState.ready);
      transcriber.hold = Completer();
      expect(await hold(relay, const Duration(seconds: 12)), isNull);
      expect(relay.listening, isNull);
      final shown = relay.entries.single;
      expect([shown.voice, shown.writing, shown.text, shown.length, shown.at], [true, true, '', const Duration(seconds: 12), now]);
      transcriber.hold!.complete('Ask the fab if the flex stiffener can be 0.2 mm');
      await relay.wordsWritten();
      final written = relay.entries.single;
      expect([written.voice, written.writing, written.text], [true, false, 'Ask the fab if the flex stiffener can be 0.2 mm']);
      expect(recordings(), [transcriber.heard.single]);
      expect([server.requests, models.requests, await store.outbox()], [isEmpty, isEmpty, isEmpty]);
      // The recording plays from this phone.
      await relay.play(written.recording!);
      expect(player.played, ['${folder.path}/voice/${transcriber.heard.single}']);
    });

    test('the app closes before the words are written: the next open writes them from the kept recording', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.hold = Completer();
      await hold(relay, const Duration(seconds: 4));
      expect((await store.pendingWords()), hasLength(1));
      relay.dispose();
      // A recording the close cut off while the button was still held has no note: it is deleted.
      await File('${folder.path}/voice/stray.wav').writeAsBytes([1]);
      transcriber.hold = null;
      final reopened = voiceController();
      await reopened.load();
      await reopened.wordsWritten();
      expect([for (final entry in reopened.entries) (entry.text, entry.writing)], [('Ask the fab if the flex stiffener can be 0.2 mm', false)]);
      expect(recordings(), hasLength(1));
      expect(recordings(), isNot(contains('stray.wav')));
    });

    test('a note whose recording is gone is dropped at the next open', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.hold = Completer();
      await hold(relay, const Duration(seconds: 4));
      relay.dispose();
      Directory('${folder.path}/voice').deleteSync(recursive: true);
      final reopened = voiceController();
      await reopened.load();
      await reopened.wordsWritten();
      expect([reopened.entries, await store.notes()], [isEmpty, isEmpty]);
    });

    test('a bump in a pocket: a 0.3 s press saves nothing and the timeline does not change', () async {
      final relay = voiceController();
      await relay.load();
      await relay.addNote('Typed one');
      final before = relay.entries.length;
      expect(await hold(relay, const Duration(milliseconds: 300)), contains('Hold the button'));
      await relay.wordsWritten();
      expect([relay.entries.length, recordings(), transcriber.heard, notices], [before, isEmpty, isEmpty, isEmpty]);
    });

    test('slide off: the note is cancelled and nothing is kept', () async {
      final relay = voiceController();
      await relay.load();
      await relay.startVoiceNote();
      clock = clock.add(const Duration(seconds: 3));
      await relay.cancelVoiceNote();
      expect(await relay.endVoiceNote(), isNull);
      expect([relay.listening, relay.entries, recordings(), transcriber.heard], [null, isEmpty, isEmpty, isEmpty]);
    });

    test('a silent recording: the app says it heard no speech, and keeps no note and no recording', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.answer = '';
      expect(await hold(relay, const Duration(seconds: 4)), isNull);
      await relay.wordsWritten();
      expect([relay.entries, await store.notes(), recordings()], [isEmpty, isEmpty, isEmpty]);
      expect(notices, ['No speech heard. Nothing was saved.']);
    });

    test('a refused microphone says where to allow it, and records nothing', () async {
      final relay = voiceController();
      await relay.load();
      microphone.allowed = false;
      expect(await relay.startVoiceNote(), contains('microphone'));
      expect(await relay.endVoiceNote(), isNull);
      expect([relay.listening, relay.entries, microphone.calls], [null, isEmpty, isEmpty]);
    });

    test('a microphone that does not start says so, and the next press records', () async {
      final relay = voiceController();
      await relay.load();
      microphone.startError = Exception('busy');
      expect(await relay.startVoiceNote(), 'The microphone did not start. Try again.');
      expect(await relay.endVoiceNote(), isNull);
      await relay.cancelVoiceNote();
      expect([relay.listening, relay.entries, recordings()], [null, isEmpty, isEmpty]);
      expect(await hold(relay, const Duration(seconds: 2)), isNull);
      await relay.wordsWritten();
      expect(relay.entries.single.text, isNotEmpty);
    });

    test('a note restored to a new phone has no recording: Play says so', () async {
      final relay = voiceController();
      await relay.load();
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      final recording = relay.entries.single.recording!;
      Directory('${folder.path}/voice').deleteSync(recursive: true);
      await relay.play(recording);
      await pumpEventQueue();
      expect([player.played, notices], [isEmpty, ['This recording is not on this phone.']]);
    });

    test('words that fail keep the note waiting; the next open tries again', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.error = Exception('engine');
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      expect(relay.entries.single.writing, isTrue);
      transcriber.error = null;
      final reopened = voiceController();
      await reopened.load();
      await reopened.wordsWritten();
      expect(reopened.entries.single.writing, isFalse);
    });

    test('first voice note: with no model, the app records nothing and gets nothing until the person says yes', () async {
      File('${folder.path}/speech-model/$modelName').deleteSync();
      final relay = voiceController();
      await relay.load();
      expect(relay.speechModel, ModelState.missing);
      expect(await relay.startVoiceNote(), isNull);
      expect([relay.listening, microphone.calls], [null, isEmpty]);
      relay.askSpeechModel();
      expect(relay.speechModel, ModelState.asking);
      relay.notNowSpeechModel();
      expect([relay.speechModel, models.requests], [ModelState.missing, isEmpty]);
      relay.askSpeechModel();
      await relay.getSpeechModel();
      expect([relay.speechModel, models.requests.length], [ModelState.ready, 1]);
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      expect(relay.entries.single.text, isNotEmpty);
    });

    test('a damaged download is deleted, voice notes stay off, and the app offers to try again', () async {
      File('${folder.path}/speech-model/$modelName').deleteSync();
      models.file = List<int>.filled(modelFile.length, 0);
      final relay = voiceController();
      await relay.load();
      await relay.getSpeechModel();
      expect([relay.speechModel, relay.modelProblem], [ModelState.failed, ModelProblem.damaged]);
      expect(await relay.startVoiceNote(), isNull);
      expect(microphone.calls, isEmpty);
      models.file = modelFile;
      await relay.getSpeechModel();
      expect(relay.speechModel, ModelState.ready);
    });

    test('remove frees the model, and the next voice note asks again', () async {
      final relay = voiceController();
      await relay.load();
      await relay.removeSpeechModel();
      expect([relay.speechModel, transcriber.closed, File('${folder.path}/speech-model/$modelName').existsSync()],
        [ModelState.missing, 1, false]);
    });

    test('with sending on, the server gets the words and the time, never the recording', () async {
      final relay = voiceController();
      await relay.load();
      expect(await relay.connect(code), isNull);
      await relay.startSending(sendEarlier: false);
      await pumpEventQueue();
      final said = now.millisecondsSinceEpoch;
      await hold(relay, const Duration(seconds: 12));
      await relay.wordsWritten();
      await pumpEventQueue();
      final sent = sentNotes().single;
      expect(sent.keys, unorderedEquals(['clientId', 'text', 'createdAt']));
      expect([sent['text'], sent['createdAt']], ['Ask the fab if the flex stiffener can be 0.2 mm', said]);
      for (final request in server.requests) {
        expect(request.body, isNot(contains('.wav')));
      }
      // This phone still shows it as a voice note it can play, now sent.
      await relay.sync();
      expect([for (final entry in relay.entries) (entry.text, entry.voice, entry.sent, entry.recording != null)],
        [(sent['text'], true, true, true)]);
    });

    test('words not written yet: the note waits on the phone, skips *Send them*, and is sent only when it has words', () async {
      final relay = voiceController();
      await relay.load();
      await relay.addNote('Typed while off');
      clock = now.add(const Duration(minutes: 1));
      transcriber.hold = Completer();
      await hold(relay, const Duration(seconds: 5));
      expect(await relay.connect(code), isNull);
      // Only the typed note is an earlier note: the voice note has no words to send.
      expect(await relay.earlierNotes(), 1);
      await relay.startSending(sendEarlier: true);
      await pumpEventQueue();
      expect([for (final note in sentNotes()) note['text']], ['Typed while off']);
      expect(relay.entries.first.writing, isTrue);
      transcriber.hold!.complete('Order more TL3312 switches');
      await relay.wordsWritten();
      await pumpEventQueue();
      expect([for (final note in sentNotes()) note['text']], ['Typed while off', 'Order more TL3312 switches']);
      expect(await relay.earlierNotes(), 0);
    });
  });

  test('makes a note id the server takes', () {
    expect(newClientId(Random(1)), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newClientId(), isNot(newClientId()));
  });
}
