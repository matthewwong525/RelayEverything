import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' show KeychainAccessibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/attachments.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/sign_in.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/sync/health.dart';
import 'package:relay_app/sync/motion.dart';
import 'package:relay_app/sync/native.dart';
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
  late FakeWebAuth webAuth;
  late FakeCalendar calendar;
  var clock = now;

  RelayController controller({NativeBackground? native, PhotoSource? photos, Network? network, Motion? motion}) => RelayController(
    store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api, signInClient: server.client,
    webAuth: webAuth.call, clock: () => clock, schedule: (on) async => scheduled.add(on), native: native, webhookFor: server.webhook,
    calendar: calendar, photos: photos, network: network, motion: motion);

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
    webAuth = FakeWebAuth();
    calendar = FakeCalendar();
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
      expect(await relay.setHealth(true), contains('Sign in'));
      expect(await relay.setHistory(true), contains('Sign in'));
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
      // After each full sync, at most each 10 minutes, the phone reads the names of what the person connected.
      expect(server.routes, ['key', 'connections', 'notes', 'connections']);
      await relay.stopSending();
      expect(relay.entries, hasLength(2));
    });
  });

  group('sending to your own webhook', () {
    List<String> hookTypes() => [
      for (final request in server.requests) if (request.url.toString() == hook.address) jsonDecode(request.body)['type'] as String,
    ];

    test('needs no key: set the webhook, test it, and each note goes there signed, and nothing to the server', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), 'Set your webhook first.');
      expect(await relay.saveWebhook('http://db.example.com/relay', fixtureSecret), 'The address must start with https://.');
      expect(await relay.testWebhook(hook.address, 'whsec_short'), startsWith('The secret must be'));
      expect(server.requests, isEmpty);
      server.answer = (_) => http.Response('', 204);
      expect(await relay.testWebhook(hook.address, fixtureSecret), 'Your receiver answered 204. It works.');
      server.answer = (_) => http.Response('', 401);
      expect(await relay.testWebhook(hook.address, fixtureSecret), 'Your receiver answered 401. Check that it has this secret.');
      server.answer = (_) => throw const SocketException('none');
      expect(await relay.testWebhook(hook.address, fixtureSecret),
        'No answer from db.example.com. Check the address, and that your receiver is running.');
      server.answer = FakeServer.ok;
      await relay.addNote('Before');
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect([relay.webhookAddress, relay.webhookSecret, relay.connected], [hook.address, fixtureSecret, false]);
      expect(await relay.startSending(sendEarlier: true, place: SendPlace.webhook), isNull);
      await relay.settled();
      await relay.addNote('After');
      await relay.settled();
      expect([relay.settings.sending, relay.settings.place, relay.status], [true, SendPlace.webhook, SyncStatus.synced]);
      expect(hookTypes(), ['webhook.test', 'webhook.test', 'webhook.test', 'note.created', 'note.created']);
      expect(server.requests.where((request) => request.url.host != 'db.example.com'), isEmpty);
      expect(server.requests.every((request) => request.headers['webhook-signature']!.startsWith('v1,')), isTrue);
      relay.dispose();
    });

    test('a switch moves what waits to the new place, and a failing receiver keeps it and shows why', () async {
      await KeyVault(storage).save(bearer);
      final relay = controller();
      await relay.load();
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.server), isNull);
      await relay.settled();
      server.answer = (request) => FakeServer.json({}, 503);
      await relay.addNote('Waits');
      await relay.settled();
      expect(relay.waiting, 1);
      await relay.saveWebhook(hook.address, fixtureSecret);
      server.requests.clear();
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      await relay.settled();
      expect([hookTypes(), relay.waiting, relay.webhookProblem?.status], [['note.created'], 1, 503]);
      expect({for (final item in await store.outbox()) item.destination}, {ownWebhook});
      server.answer = FakeServer.ok;
      await relay.sync();
      expect([relay.waiting, relay.webhookProblem, (await store.notes()).single.sentAt], [0, isNull, isNotNull]);
      expect(server.requests.where((request) => request.url.path.endsWith('/notes')), isEmpty);
      relay.dispose();
    });

    test('a deleted note goes there as note.deleted, by its clientId', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      await relay.addNote('Buy milk', id: 'n1');
      await relay.settled();
      await relay.deleteNote('n1');
      relay.dispose();
      clock = now.add(const Duration(seconds: 10));
      final next = controller();
      await next.load();
      await next.sync();
      expect([hookTypes(), next.entries, next.waiting], [['note.created', 'note.deleted'], isEmpty, 0]);
      expect(jsonDecode(server.requests.last.body)['data'], {'note': {'id': 'n1', 'deleted_at': isA<String>()}});
      next.dispose();
    });

    test('Stop sending keeps the webhook on the phone, so sending there again needs no new secret', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      await relay.stopSending();
      relay.dispose();
      final next = controller();
      await next.load();
      expect([next.settings.sending, next.webhookAddress, next.webhookSecret], [false, hook.address, fixtureSecret]);
      expect(await next.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      await next.settled();
      next.dispose();
    });

    test('a phone that lost its webhook reads sending as off, and the key stays for the server', () async {
      await store.set('settings', const Settings(sending: true, place: SendPlace.webhook).encode());
      await KeyVault(storage).save(bearer);
      final relay = controller();
      await relay.load();
      expect([relay.settings.sending, relay.connected], [false, true]);
      relay.dispose();
    });
  });

  group('the key', () {
    test('kept under the old Keychain access is saved again at start, so a locked-phone wake can send', () async {
      storage.values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      storage.access.addAll({'relay.server': null, 'relay.key': null});
      final relay = controller();
      await relay.load();
      expect(relay.connected, isTrue);
      expect(storage.values, {'relay.server': bearer.server, 'relay.key': pageKey});
      expect(storage.access.values.toSet(), {KeychainAccessibility.first_unlock_this_device});
      relay.dispose();
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
      // The round holds open its first note upload, before it reads health or queues the location point.
      expect(server.routes, ['notes']);
      expect([for (final item in await store.outbox()) item.route], ['notes', 'notes']);
      final reads = health.reads.length;
      final stopped = relay.stopSending();
      await pumpEventQueue();
      server.hold!.complete();
      await stopped;
      await pumpEventQueue();
      expect([server.routes, health.reads.length, relay.status], [['notes'], reads, SyncStatus.idle]);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
    });

    test('a note kept while a round sends goes in a round after it, before settled ends', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      await relay.setPinNotes(false);
      await relay.settled();
      server.requests.clear();
      server.hold = Completer();
      await relay.keepNote('First');
      await pumpEventQueue();
      // The round read the outbox before the second note, and holds open its upload.
      expect(server.routes, ['notes']);
      await relay.keepNote('Second');
      final done = relay.settled();
      server.hold!.complete();
      await done;
      expect([for (final note in sentNotes()) note['text']], ['First', 'Second']);
      expect(await store.waiting(), 0);
    });

    test('health starts from the moment it turns on, then reads the last 90 days a week at a time', () async {
      await KeyVault(storage).save(connection);
      final relay = controller();
      await relay.load();
      expect(await relay.startSending(sendEarlier: false), isNull);
      await relay.settled();
      expect(await relay.setHealth(true), isNull);
      await relay.settled();
      expect(health.reads, [(now.subtract(const Duration(hours: 2)), now), (now.subtract(const Duration(days: 7)), now)]);
      expect([await store.get(healthSince), await store.get(healthTypes)], ['${now.millisecondsSinceEpoch}', askedTypes]);
    });

    test('a phone that allowed health before the new types is asked once more, at open', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true, health: true).encode());
      var asked = 0;
      health = _CountingHealth(() => asked++);
      final relay = controller();
      await relay.load();
      await relay.askNewHealthTypes();
      await relay.askNewHealthTypes();
      expect([asked, await store.get(healthTypes)], [1, askedTypes]);
      // A phone with health off is not asked.
      await store.remove(healthTypes);
      await relay.stopSending();
      await relay.askNewHealthTypes();
      expect(asked, 1);
    });

    test('a background round while the new types are asked does not start the history read', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true, health: true).encode());
      await store.set(healthSince, '${now.subtract(const Duration(hours: 1)).millisecondsSinceEpoch}');
      final held = _HeldHealth();
      health = held;
      final relay = controller();
      await relay.load();
      final asking = relay.askNewHealthTypes();
      await pumpEventQueue();
      // The permission screen is open: a round reads only the new readings, and the history mark stays unset.
      await syncHealth(store, held, now: now);
      expect([await store.get(healthTypes), await store.get(healthBackfill), held.reads.length], [isNull, isNull, 1]);
      held.answer.complete(true);
      await asking;
      expect(await store.get(healthTypes), askedTypes);
    });

    test('a failed question for the new types still counts as asked', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true, health: true).encode());
      final held = _HeldHealth();
      health = held;
      final relay = controller();
      await relay.load();
      final asking = relay.askNewHealthTypes();
      await pumpEventQueue();
      held.answer.completeError(Exception('refused'));
      await asking;
      expect(await store.get(healthTypes), askedTypes);
    });

    test('the calendar turns on only with sending and its permission, lists the calendars, and sends', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings().encode());
      calendar.items = [meeting('a', now.add(const Duration(hours: 1))), meeting('h', now.add(const Duration(days: 3)), calendar: 'holidays')];
      final relay = controller();
      await relay.load();
      expect(await relay.setCalendar(true), contains('Sign in'));
      expect(await relay.startSending(sendEarlier: false), isNull);
      await relay.settled();
      calendar.allowed = false;
      expect(await relay.setCalendar(true), contains('calendar'));
      expect([relay.settings.calendar, calendar.reads], [false, isEmpty]);
      calendar.allowed = true;
      expect(await relay.setCalendar(true), isNull);
      await relay.settled();
      expect([relay.settings.calendar, [for (final c in relay.calendars) c.name], scheduled.last], [true, ['Work', 'US Holidays'], true]);
      expect(server.routes.last, 'calendar');
      expect(relay.calendarSent.at, now);
      // Turning holidays off sends its removal.
      await relay.setCalendarShown('holidays', false);
      await relay.settled();
      expect(jsonDecode(server.requests.last.body)['removed'], ['holidays:h:${now.add(const Duration(days: 3)).millisecondsSinceEpoch}']);
      expect(relay.settings.calendarsOff, {'holidays'});
    });

    test('turning the calendar off drops its waiting uploads and what was sent', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true, calendar: true).encode());
      server = FakeServer((_) => FakeServer.json({}, 503));
      calendar.items = [meeting('a', now.add(const Duration(hours: 1)))];
      final relay = controller();
      await relay.load();
      await relay.sync();
      expect([relay.calendarSent.waiting, (await store.calendarSent()).length], [1, 1]);
      expect(await relay.setCalendar(false), isNull);
      expect([relay.calendarSent.waiting, await store.calendarSent(), relay.calendars], [0, isEmpty, isEmpty]);
    });
  });

  group('settings', () {
    test('start off on a new install; sending off forces health and history off', () {
      const fresh = Settings();
      expect([fresh.sending, fresh.pinNotes, fresh.history, fresh.health], [false, false, false, false]);
      expect([const Settings(history: true, health: true).history, const Settings(history: true, health: true).health], [false, false]);
      const on = Settings(sending: true, history: true, health: true);
      expect([on.copyWith(sending: false).history, on.copyWith(sending: false).health], [false, false]);
      expect(jsonDecode(on.encode()), {'sending': true, 'pinNotes': false, 'history': true, 'health': true, 'calendar': false,
        'calendarsOff': [], 'mode': 'battery', 'place': 'server', 'privateTo': 'server',
        'photos': false, 'photosOnMobileData': false, 'appearance': 'system',
        'locationSend': 'all'});
      final back = Settings.decode(on.encode(), hasKey: false);
      expect([back.sending, back.health], [true, true]);
    });

    test('keep where private data goes: Relay Everything by default and in settings from before the choice', () {
      expect(const Settings().privateTo, SendPlace.server);
      expect(Settings.decode(jsonEncode({'sending': true, 'place': 'server'}), hasKey: true).privateTo, SendPlace.server);
      const chosen = Settings(sending: true, privateTo: SendPlace.webhook);
      expect(Settings.decode(chosen.encode(), hasKey: true).privateTo, SendPlace.webhook);
      // Off keeps the choice, so a sign-in again keeps it.
      expect(chosen.copyWith(sending: false).privateTo, SendPlace.webhook);
      expect([
        for (final place in SendPlace.values)
          for (final privateTo in SendPlace.values) Settings(place: place, privateTo: privateTo).privatePlace,
      ], [SendPlace.server, SendPlace.webhook, SendPlace.webhook, SendPlace.webhook]);
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
      // Settings saved before What to send send stays, trips and points.
      expect([old.locationSend, old.stays], [LocationSend.all, true]);
      expect(Settings.decode(jsonEncode({'pinNotes': true}), hasKey: true).photos, isFalse);
      // Photos go where sending goes: with the webhook they stay on.
      final hooked = on.copyWith(place: SendPlace.webhook);
      expect([hooked.photos, hooked.photosOnMobileData], [true, true]);
      expect(Settings.decode(hooked.encode(), hasKey: false).photos, isTrue);
    });

    test('keep the appearance by name, and settings from before it read as System', () {
      expect(const Settings().appearance, Appearance.system);
      for (final appearance in Appearance.values) {
        expect(Settings.decode(const Settings().copyWith(appearance: appearance).encode(), hasKey: false).appearance, appearance);
      }
      expect(Settings.decode(jsonEncode({'sending': false, 'pinNotes': true}), hasKey: false).appearance, Appearance.system);
      expect(Settings.decode(jsonEncode({'sending': false, 'appearance': 'sepia'}), hasKey: false).appearance, Appearance.system);
      // Turning sending off keeps the look.
      expect(const Settings(sending: true, appearance: Appearance.dark).copyWith(sending: false).appearance, Appearance.dark);
    });

    test('a picked appearance is kept on the phone and read again on the next start', () async {
      final relay = controller();
      await relay.load();
      await relay.setAppearance(Appearance.light);
      expect(relay.settings.appearance, Appearance.light);
      final reopened = controller();
      await reopened.load();
      expect(reopened.settings.appearance, Appearance.light);
    });

    test('keep the calendar and the calendars turned off, and sending off forces the calendar off', () {
      const on = Settings(sending: true, calendar: true, calendarsOff: {'holidays', 'birthdays'});
      final back = Settings.decode(on.encode(), hasKey: true);
      expect([back.calendar, back.calendarsOff], [true, {'holidays', 'birthdays'}]);
      expect([const Settings(calendar: true).calendar, on.copyWith(sending: false).calendar], [false, false]);
      expect(on.copyWith(sending: false).calendarsOff, {'holidays', 'birthdays'});
      // Saved by a version from before the calendar.
      final before = Settings.decode(jsonEncode({'sending': true, 'health': true}), hasKey: true);
      expect([before.calendar, before.calendarsOff], [false, isEmpty]);
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
      expect(jsonDecode((await store.get('settings'))!), {'sending': false, 'pinNotes': true, 'history': false, 'health': false,
        'calendar': false, 'calendarsOff': [], 'mode': 'battery', 'place': 'server', 'privateTo': 'server',
        'photos': false, 'photosOnMobileData': false, 'appearance': 'system',
        'locationSend': 'all'});
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
      expect(jsonDecode((await store.get('settings'))!), {'sending': true, 'pinNotes': true, 'history': false, 'health': true,
        'calendar': false, 'calendarsOff': [], 'mode': 'battery', 'place': 'server', 'privateTo': 'server',
        'photos': false, 'photosOnMobileData': false, 'appearance': 'system',
        'locationSend': 'all'});
      expect(places.asked, [false, true, true, false]);
      // Each change started a sync; the last round ends before the store closes.
      await relay.settled();
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
      // A device key only adds: it reads the key check, and after a full sync the names of what the person connected.
      expect([for (final request in server.requests) if (request.method == 'GET') request.url.path.split('/').last],
        ['key', 'connections']);
    });

    test('a note emptied while its first upload waits is deleted everywhere, with Undo, as the upload may be on its way',
        () async {
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await pumpEventQueue();
      await relay.addNote('# Buy', id: 'n1', sendNow: false);
      expect([relay.entries.length, relay.waiting], [1, 1]);
      expect(await relay.dropEmptyNote('n1'), Emptied.deleting);
      expect(relay.entries, isEmpty);
      await relay.endUndo('n1');
      expect([for (final request in server.requests) '${request.method} ${request.url.path.split('/').last}'],
        ['GET key', 'GET connections', 'DELETE notes']);
      expect(server.requests.last.url.queryParameters, {'clientId': 'n1'});
      expect([relay.entries, relay.waiting], [isEmpty, 0]);
      relay.dispose();
    });

    test('a note emptied with sending off, so with no upload, is dropped at once and never sent', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.addNote('# Buy', id: 'n1', sendNow: false);
      expect(relay.waiting, 0);
      expect(await relay.dropEmptyNote('n1'), Emptied.dropped);
      expect([relay.entries, await store.outbox()], [isEmpty, isEmpty]);
      expect(await relay.startSending(sendEarlier: true), isNull);
      await pumpEventQueue();
      await relay.sync();
      expect(server.requests.where((request) => request.url.path.endsWith('/notes')), isEmpty);
      relay.dispose();
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
      // The note comes while the first round runs, so it goes in a round of its own before the names are read.
      expect(server.routes, ['key', 'notes', 'connections']);
      expect([for (final request in server.requests) request.headers['Authorization']], List.filled(3, 'Bearer $pageKey'));
      expect([for (final request in server.requests) request.headers['CF-Access-Client-Id']], [null, null, null]);
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
      await store.set(healthTypes, askedTypes);
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

  group('the names of what you connected', () {
    List<String> reads() => [for (final request in server.requests) if (request.method == 'GET') request.url.path.split('/').last];

    test('are read after a full sync to the server, kept with no signal, and cleared on a new server or with sending off',
        () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true).encode());
      final relay = controller();
      await relay.load();
      expect(relay.connections, isNull);
      await relay.sync();
      expect(reads(), contains('connections'));
      expect([relay.connections?.email, relay.connections?.aiApps, relay.connections?.webhooks],
        ['ana@example.com', ['Claude'], ['Home server']]);
      // No signal: the last answer stays, also for the next start.
      server.answer = (_) => throw const SocketException('none');
      await relay.refreshConnections();
      final again = controller();
      await again.load();
      expect([relay.connections?.aiApps, again.connections?.webhooks, again.connections?.email],
        [['Claude'], ['Home server'], 'ana@example.com']);
      // A server from before the route refuses it: no names show.
      server.answer = (_) => FakeServer.json({'error': 'A device key can only send to Relay Everything.'}, 403);
      await relay.refreshConnections();
      expect(relay.connections, isNull);
      server.answer = FakeServer.ok;
      await relay.refreshConnections();
      expect(relay.connections, isNotNull);
      expect(await relay.setServer('https://preview.example.com'), isNull);
      expect([relay.connections, await store.get(connectionsKey)], [null, null]);
      await relay.refreshConnections();
      await relay.stopSending();
      expect([relay.connections, await store.get(connectionsKey)], [null, null]);
      final asked = server.requests.length;
      await relay.refreshConnections();
      expect(server.requests, hasLength(asked));
      relay.dispose();
    });

    test('are never read with sending off or to your own webhook, and go when the phone disconnects', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings().encode());
      final relay = controller();
      await relay.load();
      await relay.refreshConnections();
      expect(server.requests, isEmpty);
      await relay.saveWebhook(hook.address, fixtureSecret);
      await relay.startSending(sendEarlier: false, place: SendPlace.webhook);
      await relay.settled();
      await relay.refreshConnections();
      expect([reads(), relay.connections], [isEmpty, isNull]);
      await relay.startSending(sendEarlier: false, place: SendPlace.server);
      await relay.settled();
      expect(relay.connections?.aiApps, ['Claude']);
      await relay.disconnect();
      expect([relay.connections, await store.get(connectionsKey)], [null, null]);
      relay.dispose();
    });

    test('the Home headers the person folded are kept for the next start', () async {
      final relay = controller();
      await relay.load();
      await relay.setFolded('Notes', true);
      await relay.setFolded('On this phone', true);
      await relay.setFolded('Notes', false);
      final again = controller();
      await again.load();
      expect([relay.folded, again.folded], [{'On this phone'}, {'On this phone'}]);
    });

    test('a copy of the names kept before the email still reads, with no email', () async {
      await store.set(connectionsKey, '{"aiApps":[{"name":"Claude"}],"webhooks":[]}');
      final relay = controller();
      await relay.load();
      expect([relay.connections?.email, relay.connections?.aiApps], [null, ['Claude']]);
      final kept = Connections.decode(const Connections(email: 'ana@example.com', webhooks: ['Home server']).encode())!;
      expect([kept.email, kept.aiApps, kept.webhooks], ['ana@example.com', isEmpty, ['Home server']]);
      expect(Connections.fromJson({'email': '', 'aiApps': []}).email, isNull);
      relay.dispose();
    });
  });

  group('photos', () {
    late FakePhotos photos;
    late FakeNetwork network;
    setUp(() {
      photos = FakePhotos();
      network = FakeNetwork();
    });

    RelayController photoController() => controller(photos: photos, network: network);

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
      expect(await relay.setPhotos(true), contains('Sign in'));
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
      // The note's own sync and this one each try the photo once.
      expect([sentNotes().single['text'], photoUploads().isNotEmpty, (await store.waitingPhotos()).length, relay.status],
        ['Lunch idea', true, 1, SyncStatus.synced]);
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

    test('a move to your own webhook keeps photos on, and sends the photos waiting there as photo.created', () async {
      final relay = await sending();
      network.current = Link.mobile;
      expect(await relay.setPhotos(true), isNull);
      await relay.sync();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', later);
      await relay.sync();
      expect((await store.waitingPhotos()).length, 1);
      await relay.saveWebhook(hook.address, fixtureSecret);
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      await relay.settled();
      // On mobile data the photo still waits for Wi-Fi, at the new place too.
      expect([relay.settings.place, relay.settings.photos, (await store.waitingPhotos()).length], [SendPlace.webhook, true, 1]);
      network.current = Link.wifi;
      photos.take('IMG_0002', later.add(const Duration(minutes: 1)));
      await relay.addNote('To my database');
      await relay.settled();
      final messages = [
        for (final request in server.requests) if (request.url.toString() == hook.address) jsonDecode(request.body) as Map<String, dynamic>];
      expect([for (final message in messages) message['type']], ['note.created', 'photo.created', 'photo.created']);
      expect((messages[1]['data'] as Map)['photo'], containsPair('content_type', 'image/jpeg'));
      expect([await store.waitingPhotos(), photoUploads(), photos.asked], [isEmpty, isEmpty, 1]);
      relay.dispose();
    });

    test('with your own webhook, photos turn on and off with no question about the page', () async {
      final relay = photoController();
      await relay.load();
      await relay.saveWebhook(hook.address, fixtureSecret);
      expect(await relay.startSending(sendEarlier: false, place: SendPlace.webhook), isNull);
      expect(await relay.setPhotos(true), isNull);
      expect([relay.settings.photos, photos.asked, scheduled.last], [true, 1, true]);
      expect(await relay.setPhotos(false), isNull);
      expect([relay.settings.photos, await store.get(photosSince)], [false, null]);
      relay.dispose();
    });
  });

  group('signing in to connect', () {
    test('opens the sign-in with a challenge, trades the code with its secret, checks the key and keeps it', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.signIn(defaultServer), isNull);
      final page = webAuth.opened.single;
      expect(page.toString(), startsWith('https://app.relayeverything.com/apps/relay/sign-in/phone?'));
      expect(page.queryParameters['challenge'], matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(page.queryParameters['name'], isNotEmpty);
      final trade = server.requests.first;
      expect([trade.method, trade.url.toString(), trade.headers['Authorization']],
        ['POST', 'https://app.relayeverything.com/apps/relay/sign-in/phone/key', null]);
      final sent = jsonDecode(trade.body) as Map<String, dynamic>;
      expect(sent['code'], 'one-time-code');
      // The page keeps only the secret's SHA-256; the secret goes once, here.
      expect(challengeOf(sent['verifier'] as String), page.queryParameters['challenge']);
      expect([server.requests.last.method, server.routes.last, server.requests.last.headers['Authorization']],
        ['GET', 'key', 'Bearer $pageKey']);
      expect([relay.connected, relay.server, storage.values['relay.key']], [true, defaultServer, pageKey]);
      // Connected, sending stays off until the person's switch turns it on.
      expect(relay.settings.sending, isFalse);
    });

    test('a closed sheet or Cancel keeps no key and says nothing; a refused code says to try again', () async {
      final relay = controller();
      await relay.load();
      webAuth.back = (_) => null;
      expect(await relay.signIn(defaultServer), isNull);
      webAuth.back = (_) => Uri.parse('relayeverything://connected?error=cancelled');
      expect(await relay.signIn(defaultServer), isNull);
      expect([relay.connected, server.requests], [false, isEmpty]);
      webAuth.back = FakeWebAuth().back;
      server.answer = (_) => FakeServer.json({'error': {'code': 'invalid_input'}}, 400);
      expect(await relay.signIn(defaultServer), contains('Sign in and try again'));
      server.answer = (_) => FakeServer.json({}, 503);
      expect(await relay.signIn(defaultServer), contains('No connection'));
      expect([relay.connected, storage.values], [false, isEmpty]);
    });

    test('signs in to another server, and refuses an address that is not one', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.signIn('relay.example.com'), contains('https://'));
      expect(webAuth.opened, isEmpty);
      expect(await relay.signIn('https://relay.example.com/'), isNull);
      expect(webAuth.opened.single.host, 'relay.example.com');
      expect(server.requests.every((request) => request.url.host == 'relay.example.com'), isTrue);
      expect(relay.server, 'https://relay.example.com');
    });
  });

  group('stays and trips', () {
    late FakeMotion motion;
    setUp(() async {
      motion = FakeMotion();
      await KeyVault(storage).save(bearer);
      await store.set('settings', const Settings(sending: true).encode());
    });

    Future<void> point(DateTime at) async {
      places.points.add(Pin(at: at, lat: 43.625, lon: -79.375, accuracy: 10));
      await pumpEventQueue();
    }

    test('history asks for motion once, and Android keeps motion only while it makes stays and trips', () async {
      final relay = controller(motion: motion);
      await relay.load();
      expect(await relay.setHistory(true), isNull);
      expect(await relay.setHistory(false), isNull);
      expect(await relay.setHistory(true), isNull);
      expect(motion.asked, 1);
      expect(await relay.setLocationSend(LocationSend.points), isNull);
      expect([relay.settings.stays, motion.watching], [false, [false, true, false, true, false]]);
      relay.dispose();
    });

    test('a refused motion leaves the mode to speed, and the stays still go', () async {
      motion.allowed = false;
      final relay = controller(motion: motion);
      await relay.load();
      await relay.setHistory(true);
      await point(now);
      clock = now.add(const Duration(minutes: 40));
      await relay.sync();
      expect(server.routes, containsAll(['stays', 'locations']));
      expect(motion.asked, 1);
      relay.dispose();
    });

    test('Only stays and trips drops the points still waiting, says so, and sends no point', () async {
      final relay = controller(motion: motion);
      await relay.load();
      await relay.setHistory(true);
      await point(now);
      expect(await relay.setLocationSend(LocationSend.stays), 'The points still waiting on this phone were dropped.');
      await point(now.add(const Duration(minutes: 1)));
      clock = now.add(const Duration(minutes: 40));
      await relay.sync();
      expect(server.routes.where((route) => route == 'stays' || route == 'locations'), ['stays']);
      final stay = (jsonDecode(server.requests.singleWhere((request) => request.url.path.endsWith('/stays')).body)['stays'] as List)
        .single as Map;
      expect([stay['start'], stay['ongoing']], [now.millisecondsSinceEpoch, true]);
      expect(await relay.setLocationSend(LocationSend.stays), isNull);
      relay.dispose();
    });

    test('Only points makes no stays, asks no motion, and drops the open stay', () async {
      await store.set('settings', const Settings(sending: true, locationSend: LocationSend.points).encode());
      final relay = controller(motion: motion);
      await relay.load();
      await relay.setHistory(true);
      await point(now);
      clock = now.add(const Duration(minutes: 40));
      await relay.sync();
      expect([server.routes.contains('stays'), server.routes.contains('locations'), motion.asked], [false, true, 0]);
      expect(await store.track(), isEmpty);
      relay.dispose();
    });

    test('history off, and sending off, drop the open stay, its points and its motion', () async {
      final relay = controller(motion: motion);
      await relay.load();
      await relay.setHistory(true);
      await point(now);
      expect((await store.track()).length, 1);
      await relay.setHistory(false);
      expect([await store.track(), await store.get(timelineKey)], [isEmpty, isNull]);
      await relay.setHistory(true);
      await point(now.add(const Duration(minutes: 1)));
      clock = now.add(const Duration(minutes: 40));
      await relay.sync();
      await relay.stopSending();
      expect([await store.track(), await store.get(timelineKey), await store.waitingStays()], [isEmpty, isNull, 0]);
      relay.dispose();
    });

    test('history off, or Only points, with sending on, sends the open stay ended first, at the later of its last point and the end already sent', () async {
      final relay = controller(motion: motion);
      await relay.load();
      List<(Object?, Object?)> sent() => [
        for (final request in server.requests) if (request.url.path.endsWith('/stays'))
          for (final stay in (jsonDecode(request.body) as Map)['stays'] as List) ((stay as Map)['ongoing'], stay['end']),
      ];
      await relay.setHistory(true);
      await point(now);
      clock = now.add(const Duration(minutes: 40));
      await relay.sync();
      await relay.setHistory(false);
      await relay.sync();
      expect(sent(), [(true, clock.millisecondsSinceEpoch), (null, clock.millisecondsSinceEpoch)]);
      await relay.setHistory(true);
      final later = now.add(const Duration(minutes: 50));
      await point(later);
      clock = now.add(const Duration(minutes: 90));
      await relay.sync();
      expect(await relay.setLocationSend(LocationSend.points), isNull);
      await relay.sync();
      expect(sent().last, (null, clock.millisecondsSinceEpoch));
      expect([await store.track(), await store.get(timelineKey)], [isEmpty, isNull]);
      relay.dispose();
    });
  });

  group('on iPhone', () {
    late FakeBackground swift;

    setUp(() async {
      swift = FakeBackground();
      await KeyVault(storage).save(bearer);
      await store.set('settings', const Settings(sending: true).encode());
    });

    test('tells Swift each flag at start and on each change, and both off when sending stops', () async {
      final relay = controller(native: swift);
      await relay.load();
      expect(relay.locationModes, isTrue);
      expect(await relay.setHealth(true), isNull);
      expect(await relay.setHistory(true), isNull);
      expect(relay.settings.mode, LocationMode.battery);
      expect(await relay.setLocationMode(LocationMode.move), isNull);
      await relay.stopSending();
      expect([for (final flag in swift.flags) (flag.health, flag.history, flag.mode)], [
        (false, false, LocationMode.battery),
        (true, false, LocationMode.battery),
        (true, true, LocationMode.battery),
        (true, true, LocationMode.move),
        (false, false, LocationMode.move),
      ]);
      expect(jsonDecode((await store.get('settings'))!)['mode'], 'move');
      relay.dispose();
    });

    test('history drains the points file each minute while open, names the newest, and stops when turned off', () async {
      fakeAsync((async) {
        final relay = controller(native: swift);
        relay.load();
        async.elapse(const Duration(milliseconds: 1));
        relay.setHistory(true);
        async.elapse(const Duration(milliseconds: 1));
        expect(swift.drains, 1);
        swift.lines = [swiftPoint(now, 43.6487, -79.3817), 'not a point', swiftPoint(now.add(const Duration(minutes: 5)), 43.65, -79.38)];
        async.elapse(const Duration(minutes: 1));
        expect(swift.drains, 2);
        expect(places.lookups, [(43.65, -79.38), (43.6487, -79.3817)]);
        expect(relay.pointsSent.waiting, 2);
        relay.setHistory(false);
        async.elapse(const Duration(milliseconds: 1));
        async.elapse(const Duration(minutes: 3));
        expect(swift.drains, 2);
        relay.dispose();
      });
    });

    test('a sync moves the points in before it sends them, and history never uses the Android stream', () async {
      final relay = controller(native: swift);
      await relay.load();
      await relay.setHistory(true);
      swift.lines = [swiftPoint(now, 43.6487, -79.3817)];
      await relay.sync();
      expect(server.routes, contains('locations'));
      expect(places.points.hasListener, isFalse);
      expect([relay.pointsSent.at, relay.pointsSent.waiting], [now, 0]);
      relay.dispose();
    });

    test('Android has no modes and keeps the stream; sending off reads no points at all', () async {
      final relay = controller();
      await relay.load();
      expect(relay.locationModes, isFalse);
      await relay.setHistory(true);
      expect(places.points.hasListener, isTrue);
      await relay.stopSending();
      expect(places.points.hasListener, isFalse);
      final iphone = controller(native: swift);
      await iphone.load();
      await iphone.sync();
      expect(swift.drains, 0);
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
      // The next open of the app has its own transcriber: the closed one still holds the first words.
      transcriber = FakeTranscriber();
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

    test('Hold to talk: the tip shows until a first voice note starts, also after a restart; a failed start keeps it', () async {
      final relay = voiceController();
      await relay.load();
      expect(relay.holdTipSeen, isFalse);
      microphone.allowed = false;
      expect(await relay.startVoiceNote(), contains('microphone'));
      microphone.allowed = true;
      microphone.startError = Exception('busy');
      expect(await relay.startVoiceNote(), 'The microphone did not start. Try again.');
      expect([relay.holdTipSeen, await store.get(holdTipKey)], [false, null]);
      expect(await relay.startVoiceNote(), isNull);
      expect(relay.holdTipSeen, isTrue);
      await relay.cancelVoiceNote();
      relay.dispose();
      final reopened = voiceController();
      await reopened.load();
      expect(reopened.holdTipSeen, isTrue);
    });

    test('the sound level shows only while it listens, and ends when the note is saved or cancelled', () async {
      final relay = voiceController();
      await relay.load();
      expect(relay.level, isNull);
      microphone.heard = [0.4, 0.7];
      await relay.startVoiceNote();
      expect(await relay.level!.take(2).toList(), [0.4, 0.7]);
      var ended = relay.level!.toList();
      clock = clock.add(const Duration(seconds: 2));
      expect(await relay.endVoiceNote(), isNull);
      expect([await ended, relay.level], [isEmpty, isNull]);
      microphone.heard = const [];
      await relay.startVoiceNote();
      ended = relay.level!.toList();
      await relay.cancelVoiceNote();
      expect([await ended, relay.level], [isEmpty, isNull]);
      await relay.wordsWritten();
    });

    test('a bump in a pocket: a 0.3 s press saves nothing and the timeline does not change', () async {
      final relay = voiceController();
      await relay.load();
      await relay.addNote('Typed one');
      final before = relay.entries.length;
      expect(await hold(relay, const Duration(milliseconds: 300)), 'Too short to keep. Nothing was saved.');
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

    test('a microphone that does not stop says so, closes the card and keeps nothing; Cancel then does no harm', () async {
      final relay = voiceController();
      await relay.load();
      microphone.stopError = Exception('stuck');
      expect(await hold(relay, const Duration(seconds: 3)), 'The microphone did not stop right. Nothing was saved.');
      await relay.cancelVoiceNote();
      await relay.wordsWritten();
      expect([relay.listening, relay.entries, await store.notes(), recordings(), transcriber.heard], [null, isEmpty, isEmpty, isEmpty, isEmpty]);
    });

    test('a voice note the phone cannot keep, such as on a full disk, says so, closes the card and keeps nothing', () async {
      await store.close();
      store = _FullStore();
      final relay = voiceController();
      await relay.load();
      expect(await hold(relay, const Duration(seconds: 3)), 'The voice note did not save.');
      await relay.wordsWritten();
      expect([relay.listening, relay.entries, await store.notes(), recordings(), transcriber.heard], [null, isEmpty, isEmpty, isEmpty, isEmpty]);
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

    test('words that fail keep the note and its recording, show the failed state, and the next open tries again', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.error = Exception('engine');
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      final failed = relay.entries.single;
      expect([failed.writing, failed.failed, failed.recording, recordings()], [false, true, isNotNull, hasLength(1)]);
      await pumpEventQueue();
      expect(notices, ['The words did not come. Tap Try again on the note.']);
      transcriber.error = null;
      final reopened = voiceController();
      await reopened.load();
      await reopened.wordsWritten();
      expect([reopened.entries.single.writing, reopened.entries.single.failed], [false, false]);
      expect(reopened.entries.single.text, isNotEmpty);
    });

    test('an Error, not only an Exception, leaves no note on Writing the words, and the notice shows once', () async {
      final relay = voiceController();
      await relay.load();
      // Such as Isolate.run refusing a closure that holds a Future, or a speech part missing from the build.
      transcriber.error = ArgumentError('Invalid argument: is a regular instance reachable via : Instance of Future');
      await hold(relay, const Duration(seconds: 3));
      clock = clock.add(const Duration(seconds: 10));
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      expect([for (final entry in relay.entries) (entry.writing, entry.failed)], [(false, true), (false, true)]);
      expect(await store.pendingWords(), hasLength(2));
      await pumpEventQueue();
      expect(notices, ['The words did not come. Tap Try again on the note.']);
    });

    test('words that never end stop at the time limit, the writing is cancelled, and the note shows failed', () async {
      final limits = <Duration>[];
      final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
        clock: () => clock, schedule: (on) async => scheduled.add(on),
        voice: fakeVoice(folder, models, clock: () => clock, microphone: microphone, transcriber: transcriber, player: player),
        wordsLimit: (length) {
          limits.add(length);
          return const Duration(milliseconds: 20);
        });
      relay.notices.listen(notices.add);
      await relay.load();
      transcriber.hold = Completer();
      await hold(relay, const Duration(seconds: 3));
      await relay.wordsWritten();
      expect(limits, [const Duration(seconds: 3)]);
      expect(transcriber.cancelled, 1);
      expect([relay.entries.single.writing, relay.entries.single.failed], [false, true]);
      await pumpEventQueue();
      expect(notices, ['The words did not come. Tap Try again on the note.']);
    });

    test('the time limit is 2 minutes, or the recording\'s length when it is longer', () {
      expect(wordsLimitOf(const Duration(seconds: 3)), const Duration(minutes: 2));
      expect(wordsLimitOf(const Duration(minutes: 2)), const Duration(minutes: 2));
      expect(wordsLimitOf(const Duration(minutes: 5)), const Duration(minutes: 5));
    });

    test('Try again writes the words of a failed note from its kept recording', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.error = StateError('engine');
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      expect(relay.entries.single.failed, isTrue);
      transcriber.error = null;
      transcriber.hold = Completer();
      await relay.writeWordsAgain();
      expect([relay.entries.single.writing, relay.entries.single.failed], [true, false]);
      transcriber.hold!.complete('Order more TL3312 switches');
      await relay.wordsWritten();
      final written = relay.entries.single;
      expect([written.text, written.writing, written.failed], ['Order more TL3312 switches', false, false]);
      expect(transcriber.heard, hasLength(2));
      expect(transcriber.heard.toSet(), hasLength(1));
      await pumpEventQueue();
      expect(notices, ['The words did not come. Tap Try again on the note.']);
    });

    test('two notes at once: the second waits its turn past its own time limit, and cancels neither note', () async {
      // A 5-minute note, then at once a 3-second one: the short one's limit is short, and starts only at its turn.
      final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
        clock: () => clock, schedule: (on) async => scheduled.add(on),
        voice: fakeVoice(folder, models, clock: () => clock, microphone: microphone, transcriber: transcriber, player: player),
        wordsLimit: (length) => length >= const Duration(minutes: 5) ? const Duration(hours: 1) : const Duration(milliseconds: 20));
      relay.notices.listen(notices.add);
      await relay.load();
      final first = transcriber.hold = Completer();
      await hold(relay, const Duration(minutes: 5));
      await pumpEventQueue();
      expect(transcriber.heard, hasLength(1));
      transcriber.hold = null;
      clock = clock.add(const Duration(seconds: 10));
      await hold(relay, const Duration(seconds: 3));
      // Longer than the second note's limit, while it waits.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(transcriber.cancelled, 0);
      expect(transcriber.heard, hasLength(1));
      expect([for (final entry in relay.entries) (entry.writing, entry.failed)], [(true, false), (true, false)]);
      first.complete('Order more TL3312 switches');
      await relay.wordsWritten();
      expect(transcriber.heard, hasLength(2));
      expect([for (final entry in relay.entries) (entry.text, entry.writing, entry.failed)], [
        ('Ask the fab if the flex stiffener can be 0.2 mm', false, false),
        ('Order more TL3312 switches', false, false),
      ]);
      expect([transcriber.cancelled, notices], [0, isEmpty]);
    });

    test('a stuck job that its cancel does not stop: the note behind it still ends failed, and never starts', () async {
      final relay = RelayController(store: store, vault: KeyVault(storage), places: places, health: health, apiFor: server.api,
        clock: () => clock, schedule: (on) async => scheduled.add(on),
        voice: fakeVoice(folder, models, clock: () => clock, microphone: microphone, transcriber: transcriber, player: player),
        wordsLimit: (length) => const Duration(milliseconds: 20));
      relay.notices.listen(notices.add);
      await relay.load();
      transcriber.cancelStops = false;
      final stuck = transcriber.hold = Completer();
      await hold(relay, const Duration(seconds: 4));
      await pumpEventQueue();
      clock = clock.add(const Duration(seconds: 10));
      await hold(relay, const Duration(seconds: 3));
      // Past both limits: the first's, then the second's, which starts when the first passes its own.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(transcriber.cancelled, 1);
      expect(transcriber.heard, hasLength(1));
      expect([for (final entry in relay.entries) (entry.writing, entry.failed)], [(false, true), (false, true)]);
      // The stuck job ends at last: the second note, past its limit, never starts its own job.
      stuck.complete('Order more TL3312 switches');
      await relay.wordsWritten();
      await pumpEventQueue();
      expect(transcriber.heard, hasLength(1));
      expect(notices, ['The words did not come. Tap Try again on the note.']);
    });

    test('Try again writes only the failed notes, not a note whose words are being written now', () async {
      final relay = voiceController();
      await relay.load();
      transcriber.error = StateError('engine');
      await hold(relay, const Duration(seconds: 2));
      await relay.wordsWritten();
      final failed = transcriber.heard.single;
      transcriber.error = null;
      final held = transcriber.hold = Completer();
      clock = clock.add(const Duration(seconds: 10));
      await hold(relay, const Duration(seconds: 3));
      await pumpEventQueue();
      final writing = transcriber.heard.last;
      expect(writing, isNot(failed));
      await relay.writeWordsAgain();
      held.complete('Order more TL3312 switches');
      await relay.wordsWritten();
      expect(transcriber.heard, [failed, writing, failed]);
      expect([for (final entry in relay.entries) (entry.writing, entry.failed)], [(false, false), (false, false)]);
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

  group('deleting a note', () {
    List<http.Request> deletes() => [for (final request in server.requests) if (request.method == 'DELETE') request];

    /// A controller sending to the server, with the note `n1` sent.
    RelayController sentNote(FakeAsync async) {
      final relay = controller();
      relay.load();
      async.elapse(const Duration(milliseconds: 1));
      relay.connect(pageCode);
      async.elapse(const Duration(milliseconds: 1));
      relay.startSending(sendEarlier: false);
      async.elapse(const Duration(milliseconds: 1));
      relay.addNote('# Buy milk', id: 'n1');
      async.elapse(const Duration(milliseconds: 1));
      expect([relay.entries.single.sent, sentNotes().length], [true, 1]);
      return relay;
    }

    test('leaves the list at once, and when the Undo bar closes with no Undo its delete goes to the server', () {
      fakeAsync((async) {
        final relay = sentNote(async);
        relay.deleteNote('n1');
        expect(relay.entries, isEmpty);
        // Past the bar's own five seconds: a bar that slid in late, or waited behind another, still shows Undo.
        async.elapse(undoTime + const Duration(seconds: 2));
        expect(deletes(), isEmpty);
        relay.endUndo('n1');
        async.elapse(const Duration(milliseconds: 1));
        expect([for (final request in deletes()) request.url.queryParameters], [{'clientId': 'n1'}]);
        expect(relay.entries, isEmpty);
        async.elapse(deleteAfter);
        expect(deletes().length, 1);
        relay.dispose();
      });
    });

    test('with no bar to close, the delete runs after deleteAfter, longer than the bar shows', () {
      fakeAsync((async) {
        final relay = sentNote(async);
        relay.deleteNote('n1');
        async.elapse(deleteAfter - const Duration(milliseconds: 100));
        expect(deletes(), isEmpty);
        async.elapse(const Duration(milliseconds: 200));
        expect([for (final request in deletes()) request.url.queryParameters], [{'clientId': 'n1'}]);
        relay.dispose();
      });
    });

    test('a bar that closes while the mark is still written runs the delete once', () {
      fakeAsync((async) {
        final relay = sentNote(async);
        relay.deleteNote('n1');
        relay.endUndo('n1');
        async.elapse(const Duration(milliseconds: 1));
        expect([deletes().length, relay.entries], [1, isEmpty]);
        async.elapse(deleteAfter);
        expect([deletes().length, relay.entries], [1, isEmpty]);
        relay.dispose();
      });
    });

    test('Undo in its time brings the note back and sends nothing', () {
      fakeAsync((async) {
        final relay = sentNote(async);
        relay.deleteNote('n1');
        async.elapse(const Duration(seconds: 2));
        relay.undoDelete('n1');
        async.elapse(const Duration(milliseconds: 1));
        expect(relay.entries.single.id, 'n1');
        // The bar closes after its Undo, as when the person taps Undo and the bar times out after.
        relay.endUndo('n1');
        async.elapse(deleteAfter * 2);
        expect([deletes(), relay.entries.length], [isEmpty, 1]);
        relay.dispose();
      });
    });

    test('a close in the Undo time deletes the note when the time ends, at the next start', () {
      fakeAsync((async) {
        final relay = sentNote(async);
        relay.deleteNote('n1');
        async.elapse(const Duration(seconds: 1));
        relay.dispose();
        clock = now.add(const Duration(seconds: 2));
        final next = controller();
        next.load();
        async.elapse(const Duration(milliseconds: 1));
        expect([next.entries, deletes()], [isEmpty, isEmpty]);
        // Its mark was made at `now`, so with the clock at 2 s its deleteAfter ends 8 s after this start.
        async.elapse(deleteAfter - const Duration(seconds: 2) - const Duration(milliseconds: 10));
        expect(deletes(), isEmpty);
        async.elapse(const Duration(milliseconds: 20));
        expect([for (final request in deletes()) request.url.queryParameters], [{'clientId': 'n1'}]);
        next.dispose();
      });
    });

    test('with sending off waits on the phone, and goes when sending is on again, before the pull', () async {
      // The server gives the note to each pull until its delete lands, so a pull before the delete would bring it back.
      var gone = false;
      server.answer = (request) {
        if (request.method == 'DELETE') gone = true;
        if (request.method != 'GET' || !request.url.path.endsWith('/notes')) return FakeServer.ok(request);
        return notesPage([
          if (gone) {'id': 's1', 'clientId': 'n1', 'deleted': true}
          else pulledNote('s1', clientId: 'n1', mine: true, text: '# Buy milk', recordedAt: now),
        ], next: gone ? 2 : 1);
      };
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.addNote('# Buy milk', id: 'n1');
      await pumpEventQueue();
      await relay.pullNotes();
      await relay.settled();
      expect(relay.entries.single.id, 'n1');
      await relay.stopSending();
      await relay.deleteNote('n1');
      relay.dispose();
      clock = now.add(deleteAfter);
      final next = controller();
      await next.load();
      await next.sync();
      await next.pullNotes();
      await next.settled();
      expect([next.entries, deletes(), await store.waiting()], [isEmpty, isEmpty, 1]);
      server.requests.clear();
      expect(await next.startSending(sendEarlier: false), isNull);
      await pumpEventQueue();
      await next.pullNotes();
      await next.settled();
      final calls = [for (final request in server.requests) if (request.method == 'DELETE' || request.url.path.endsWith('/notes'))
        '${request.method} ${request.url.path.split('/').last}'];
      expect(calls, ['DELETE notes', 'GET notes']);
      expect([next.entries, await store.notes(), await store.waiting()], [isEmpty, isEmpty, 0]);
      next.dispose();
    });

    test('an emptied note the server has is deleted everywhere, with Undo', () async {
      final relay = controller();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.addNote('# Buy milk', id: 'n1');
      await pumpEventQueue();
      await relay.sync();
      expect(relay.entries.single.sent, isTrue);
      expect(await relay.dropEmptyNote('n1'), Emptied.deleting);
      expect(relay.entries, isEmpty);
      await relay.undoDelete('n1');
      expect(relay.entries.single.id, 'n1');
      relay.dispose();
    });
  });

  group('files', () {
    late Directory folder;
    setUp(() => folder = tempFolder());

    RelayController withFiles({FileOpener? opener}) => RelayController(store: store, vault: KeyVault(storage), places: places,
      health: health, apiFor: server.api, clock: () => clock, folder: () async => folder, opener: opener);

    NewFile picked(String name, List<int> bytes, {int? size}) {
      final source = File('${folder.path}/picked/$name')..createSync(recursive: true)..writeAsBytesSync(bytes);
      return NewFile(path: source.path, name: name, size: size ?? bytes.length);
    }

    test('a note can be files alone: the phone keeps its own copy, and sending off makes no request', () async {
      server = noNetwork();
      final relay = withFiles();
      await relay.load();
      expect(await relay.addNote('  ', files: [picked('receipt.jpg', [1, 2, 3]), picked('warranty.pdf', [4, 5])]), isNull);
      final entry = relay.entries.single;
      expect(entry.text, '');
      expect([for (final file in entry.files) (file.name, file.type, file.size, file.picture)],
        [('receipt.jpg', 'image/jpeg', 3, true), ('warranty.pdf', 'application/pdf', 2, false)]);
      for (final file in entry.files) {
        expect(file.path, startsWith('${folder.path}/attachments/'));
      }
      expect(File(entry.files.first.path).readAsBytesSync(), [1, 2, 3]);
      expect(entry.files.last.path, endsWith('.pdf'));
      // The app copied the picked file and left it where it was.
      expect(File('${folder.path}/picked/receipt.jpg').existsSync(), isTrue);
      await relay.sync();
      expect([server.requests, await store.outbox()], [isEmpty, isEmpty]);
    });

    test('a file over 25 MB, or an eleventh file, is left out with a message, and the rest are kept', () async {
      final relay = withFiles();
      await relay.load();
      final big = picked('video.mov', [0], size: maxFileBytes + 1);
      final problem = await relay.addNote('Lots', files: [big, for (var i = 0; i < 11; i++) picked('p$i.png', [i])]);
      expect(problem, contains('video.mov is over 25 MB'));
      expect(problem, contains('1 file was not added'));
      expect(relay.entries.single.files, hasLength(10));
      // Nothing to keep: no note at all.
      expect(await relay.addNote('', files: [big]), endsWith('Give the note words or a file.'));
      expect(await relay.addNote(' '), 'Give the note words or a file.');
      expect(relay.entries, hasLength(1));
    });

    test('with sending on, each note goes first, then its files; Send them sends an earlier note\'s files too', () async {
      final relay = withFiles();
      await relay.load();
      await relay.addNote('Earlier', files: [picked('old.pdf', [9])]);
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: true);
      await relay.sync();
      clock = now.add(const Duration(minutes: 1));
      await relay.addNote('New', files: [picked('new.jpg', [1, 2])]);
      await relay.sync();
      expect(server.routes, ['key', 'notes', 'attachments', 'connections', 'notes', 'attachments']);
      final uploads = [for (final request in server.requests) if (request.url.path.endsWith('attachments')) request];
      expect([for (final upload in uploads) upload.bodyBytes], [[9], [1, 2]]);
      final notes = sentNotes();
      expect(notes.first['attachments'],
        [{'id': uploads.first.headers['X-Attachment-Id'], 'name': 'old.pdf', 'type': 'application/pdf', 'size': 1}]);
      expect([for (final upload in uploads) upload.headers['X-Note-Client-Id']], [for (final note in notes) note['clientId']]);
      expect(relay.waiting, 0);
    });

    test('a change to a sent note sends its words, then its new files; past ten files it says so', () async {
      final relay = withFiles();
      await relay.load();
      expect(await relay.connect(pageCode), isNull);
      await relay.startSending(sendEarlier: false);
      await relay.addNote('Desk lamp', id: 'n1', files: [for (var i = 0; i < 9; i++) picked('p$i.png', [i])]);
      await relay.sync();
      server.requests.clear();
      final problem = await relay.editNote('n1', '# Desk lamp', files: [picked('a.pdf', [7]), picked('b.pdf', [8])]);
      expect(problem, contains('1 file was not added'));
      await relay.sync();
      expect(server.routes, ['notes', 'attachments']);
      expect([server.requests.first.method, jsonDecode(server.requests.first.body)['text']], ['PATCH', '# Desk lamp']);
      expect([relay.entries.single.text, relay.entries.single.files.length, relay.waiting], ['# Desk lamp', 10, 0]);
    });

    test('opens a file with the phone, and says when it is gone or no app opens it', () async {
      final opened = <(String, String)>[];
      var opens = true;
      final relay = withFiles(opener: (file, type) async {
        opened.add((file.path, type));
        return opens;
      });
      await relay.load();
      final notices = <String>[];
      relay.notices.listen(notices.add);
      await relay.addNote('', files: [picked('warranty.pdf', [1])]);
      final file = relay.entries.single.files.single;
      await relay.openFile(file);
      expect(opened, [(file.path, 'application/pdf')]);
      opens = false;
      await relay.openFile(file);
      File(file.path).deleteSync();
      await relay.openFile(file);
      await pumpEventQueue();
      expect(notices, ['No app on this phone opens this file.', 'This file is not on this phone.']);
      expect(opened, hasLength(2));
    });
  });

  group('private data only to your own webhook', () {
    late FakePhotos photos;
    late FakeNetwork network;
    setUp(() {
      photos = FakePhotos();
      network = FakeNetwork();
    });

    bool toHook(http.Request request) => request.url.toString() == hook.address;
    List<String> hookTypes() => [for (final request in server.requests) if (toHook(request)) jsonDecode(request.body)['type'] as String];
    List<String> serverRoutes() => [for (final request in server.requests) if (!toHook(request)) request.url.path.split('/').last];
    const private = {'health', 'locations', 'calendar', 'photos'};

    /// Signed in to Relay Everything with health and the calendar on, and a reading and an event to send.
    Future<RelayController> signedIn({Settings settings = const Settings(sending: true, health: true, calendar: true)}) async {
      await KeyVault(storage).save(connection);
      await store.set('settings', settings.encode());
      await store.set(healthTypes, askedTypes);
      health.readings = [reading(HealthDataType.STEPS, now.subtract(const Duration(minutes: 30)), now, value: 10)];
      calendar.items = [meeting('a', now.add(const Duration(hours: 1)))];
      final relay = controller(photos: photos, network: network);
      await relay.load();
      return relay;
    }

    test('notes go to Relay Everything, and health, points, the calendar and a photo only to the webhook', () async {
      final relay = await signedIn();
      expect(await relay.setPrivatePlace(SendPlace.webhook), 'Set your webhook first.');
      expect(relay.settings.privateTo, SendPlace.server);
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.setPrivatePlace(SendPlace.webhook), isNull);
      await relay.settled();
      expect(await relay.setPhotos(true), isNull);
      await relay.settled();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', clock);
      await store.addPoint(Pin(at: clock, lat: 43.6, lon: -79.3, accuracy: 5));
      await relay.addNote('Lunch idea');
      await relay.settled();
      expect([for (final note in sentNotes()) note['text']], ['Lunch idea']);
      expect(serverRoutes().where(private.contains), isEmpty);
      expect(hookTypes().toSet(), {'health.samples', 'calendar.events', 'location.points', 'photo.created'});
      expect([relay.settings.place, relay.settings.privatePlace, relay.status, relay.privateWebhookMissing],
        [SendPlace.server, SendPlace.webhook, SyncStatus.synced, false]);
      expect([await store.outbox(), await store.waitingPhotos()], [isEmpty, isEmpty]);
      relay.dispose();
    });

    test('a receiver that answers 503 holds back no note, and a switch back sends what waits to Relay Everything', () async {
      final relay = await signedIn();
      server.answer = (request) => toHook(request) ? http.Response('', 503) : FakeServer.ok(request);
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.setPrivatePlace(SendPlace.webhook), isNull);
      await relay.settled();
      clock = now.add(const Duration(minutes: 5));
      await relay.addNote('Still syncs');
      await relay.settled();
      expect([for (final note in sentNotes()) note['text']], ['Still syncs']);
      expect([relay.status, relay.webhookProblem?.status], [SyncStatus.synced, 503]);
      expect([relay.healthSent.waiting, relay.calendarSent.waiting], [greaterThan(0), 1]);
      expect({for (final item in await store.outbox()) (item.route, item.destination)},
        {('health', ownWebhook), ('calendar', ownWebhook)});
      expect(serverRoutes().where(private.contains), isEmpty);
      final asked = hookTypes().length;
      expect(await relay.setPrivatePlace(SendPlace.server), isNull);
      await relay.settled();
      expect([relay.settings.privateTo, await store.outbox()], [SendPlace.server, isEmpty]);
      expect(serverRoutes(), containsAll(['health', 'calendar']));
      expect(hookTypes().length, asked);
      relay.dispose();
    });

    test('a new private place says not sent yet until it takes data, never the time of the old place', () async {
      final relay = await signedIn();
      await relay.sync();
      await relay.settled();
      expect([relay.healthSent.at, relay.calendarSent.at], [isNotNull, isNotNull]);
      server.answer = (request) => toHook(request) ? http.Response('', 503) : FakeServer.ok(request);
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.setPrivatePlace(SendPlace.webhook), isNull);
      await relay.settled();
      expect([relay.healthSent.at, relay.pointsSent.at, relay.calendarSent.at], [null, null, null]);
      relay.dispose();
    });

    test('Sign out keeps the choice and the webhook, so a sign-in again sends private data there', () async {
      final relay = await signedIn();
      await relay.saveWebhook(hook.address, fixtureSecret);
      await relay.setPrivatePlace(SendPlace.webhook);
      await relay.settled();
      await relay.disconnect();
      expect([relay.settings.sending, relay.settings.privateTo, relay.webhookAddress], [false, SendPlace.webhook, hook.address]);
      relay.dispose();
      final next = controller();
      await next.load();
      expect([next.settings.privateTo, next.webhookAddress, next.connected], [SendPlace.webhook, hook.address, false]);
      next.dispose();
    });

    test('a webhook lost in a restore keeps sending on: notes go, private data waits and never goes to the server', () async {
      final relay = await signedIn(settings: const Settings(sending: true, health: true, privateTo: SendPlace.webhook));
      expect([relay.settings.sending, relay.privateWebhookMissing, relay.webhookAddress], [true, true, isNull]);
      await relay.addNote('Goes');
      await relay.settled();
      expect([for (final note in sentNotes()) note['text']], ['Goes']);
      expect(serverRoutes().where(private.contains), isEmpty);
      expect(relay.healthSent.waiting, greaterThan(0));
      expect({for (final item in await store.outbox()) item.destination}, {ownWebhook});
      // Set again: what waited goes there.
      expect(await relay.saveWebhook(hook.address, fixtureSecret), isNull);
      expect(await relay.setPrivatePlace(SendPlace.webhook), isNull);
      await relay.settled();
      expect([relay.privateWebhookMissing, relay.healthSent.waiting, hookTypes().toSet()], [false, 0, {'health.samples'}]);
      expect(serverRoutes().where(private.contains), isEmpty);
      relay.dispose();
    });
  });

  group('notes first', () {
    bool isPull(http.Request request) => request.method == 'GET' && request.url.path.endsWith('/notes');
    /// The note and health calls, in order, as `POST notes`, `GET notes`, `POST health`.
    List<String> calls() => [for (final request in server.requests)
      if (const {'notes', 'health'}.contains(request.url.path.split('/').last)) '${request.method} ${request.url.path.split('/').last}'];
    Future<void> queueHealth(int value) => store.queueSamples([
      {'type': 'steps', 'start': 1, 'end': 2, 'value': value, 'unit': 'count', 'source': 'Health'}]);

    /// Signed in to Relay Everything, with pins off, and the server giving one note from elsewhere to each pull.
    Future<RelayController> signedIn() async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true).encode());
      server.answer = (request) => isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request);
      final relay = controller();
      await relay.load();
      await relay.setPinNotes(false);
      await relay.settled();
      server.requests.clear();
      return relay;
    }

    test('a pull sends the note, then shows the note from elsewhere, before the health readings send', () async {
      final relay = await signedIn();
      await queueHealth(10);
      await relay.addNote('Lunch idea', sendNow: false);
      List<String?>? shownAtHealth;
      server.answer = (request) {
        if (request.url.path.endsWith('/health')) shownAtHealth ??= [for (final entry in relay.entries) entry.from];
        return isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request);
      };
      await relay.pullNotes();
      await relay.settled();
      expect(calls(), ['POST notes', 'GET notes', 'POST health']);
      expect(shownAtHealth, containsAll([null, 'Email']));
      expect(await store.outbox(), isEmpty);
    });

    test('a failed health upload still pulls, keeps the health on the phone, and Home shows Synced', () async {
      final relay = await signedIn();
      await queueHealth(10);
      server.answer = (request) => request.url.path.endsWith('/health') ? FakeServer.json({}, 503)
        : isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request);
      await relay.sync();
      expect([relay.status, [for (final item in await store.outbox()) item.route]], [SyncStatus.synced, ['health']]);
      await relay.pullNotes();
      await relay.settled();
      expect(calls(), ['POST health', 'GET notes', 'POST health']);
      expect([relay.status, relay.entries.single.from, [for (final item in await store.outbox()) item.route]],
        [SyncStatus.synced, 'Email', ['health']]);
    });

    test('a pull ends, and Home shows Synced, while the health readings still send', () async {
      final relay = await signedIn();
      await queueHealth(10);
      // The pull's answer holds open each call after it, so the health upload is still on its way.
      server.answer = (request) {
        if (!isPull(request)) return FakeServer.ok(request);
        server.hold = Completer();
        return notesPage([pulledNote('s1')], next: 1);
      };
      final statuses = <SyncStatus>[];
      relay.addListener(() => statuses.add(relay.status));
      await relay.pullNotes();
      await pumpEventQueue();
      expect([calls(), relay.status, relay.entries.single.from], [['GET notes', 'POST health'], SyncStatus.synced, 'Email']);
      expect([for (final item in await store.outbox()) item.route], ['health']);
      server.hold!.complete();
      await relay.settled();
      expect([await store.outbox(), relay.status], [isEmpty, SyncStatus.synced]);
      // Syncing showed once, for the notes alone.
      expect(statuses.where((status) => status == SyncStatus.syncing).length, 1);
    });

    test('a note kept while health readings send goes before the readings still waiting', () async {
      final relay = await signedIn();
      await queueHealth(10);
      await queueHealth(20);
      server.hold = Completer();
      final round = relay.sync();
      await pumpEventQueue();
      expect(calls(), ['POST health']);
      await relay.keepNote('Lunch idea');
      server.hold!.complete();
      await round;
      await relay.settled();
      expect(calls(), ['POST health', 'POST notes', 'POST health']);
      expect([for (final request in server.requests) if (request.url.path.endsWith('/health'))
        ((jsonDecode(request.body) as Map)['samples'] as List).single['value']], [10, 20]);
      expect([await store.outbox(), relay.status], [isEmpty, SyncStatus.synced]);
    });

    test('a pull asked for while health readings send stops them, and reads the notes before the rest', () async {
      final relay = await signedIn();
      await queueHealth(10);
      await queueHealth(20);
      server.hold = Completer();
      final round = relay.sync();
      await pumpEventQueue();
      final pulled = relay.pullNotes();
      server.hold!.complete();
      await pulled;
      expect(calls().take(2), ['POST health', 'GET notes']);
      await round;
      await relay.settled();
      expect(calls(), ['POST health', 'GET notes', 'POST health']);
    });

    test('a failed photo upload does not stop notes: the pull reads, and the photo waits for a later round', () async {
      await KeyVault(storage).save(connection);
      await store.set('settings', const Settings(sending: true, photos: true).encode());
      await store.set(photosSince, '${now.millisecondsSinceEpoch}');
      final photos = FakePhotos();
      final relay = controller(photos: photos, network: FakeNetwork());
      await relay.load();
      await relay.setPinNotes(false);
      await relay.settled();
      server.requests.clear();
      clock = now.add(const Duration(minutes: 5));
      photos.take('IMG_0001', now.add(const Duration(minutes: 1)));
      server.answer = (request) => request.url.path.endsWith('/photos') ? FakeServer.json({}, 503)
        : isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request);
      await relay.pullNotes();
      await relay.settled();
      expect([for (final request in server.requests) if (isPull(request) || request.url.path.endsWith('/photos'))
        '${request.method} ${request.url.path.split('/').last}'], ['GET notes', 'POST photos']);
      expect([relay.status, relay.entries.single.from, (await store.waitingPhotos()).length], [SyncStatus.synced, 'Email', 1]);
    });

    test('a pull ends when the round fails before it reads, so no wait is left open', () async {
      await store.close();
      store = _BrokenOutboxStore();
      final relay = await signedIn();
      (store as _BrokenOutboxStore).broken = true;
      final errors = <Object>[];
      await runZonedGuarded(() async {
        await relay.pullNotes();
        await pumpEventQueue();
      }, (error, _) => errors.add(error));
      expect([calls(), errors], [isEmpty, [isA<StateError>()]]);
    });

    test('a pull with sending off, or with no signal, ends at once and reads nothing', () async {
      final relay = await signedIn();
      await relay.addNote('Waits', sendNow: false);
      server.answer = (_) => FakeServer.json({}, 502);
      await relay.pullNotes();
      expect([calls(), relay.status], [['POST notes'], SyncStatus.offline]);
      await relay.stopSending();
      server.requests.clear();
      await relay.pullNotes();
      await relay.settled();
      expect([server.requests, relay.status], [isEmpty, SyncStatus.idle]);
    });
  });

  test('makes a note id the server takes', () {
    expect(newClientId(Random(1)), matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(newClientId(), isNot(newClientId()));
  });
}

/// Health that counts each ask for its permission.
class _CountingHealth extends FakeHealth {
  _CountingHealth(this.onAsk);

  final void Function() onAsk;

  @override
  Future<bool> allow() async {
    onAsk();
    return true;
  }
}

/// Holds the health question open until the test completes [answer].
class _HeldHealth extends FakeHealth {
  final answer = Completer<bool>();

  @override
  Future<bool> allow() => answer.future;
}

/// A store whose outbox can not be read once [broken], such as a database that failed: a round stops with an error.
class _BrokenOutboxStore extends Store {
  _BrokenOutboxStore() : super(NativeDatabase.memory(), folder: () async => tempFolder());

  bool broken = false;

  @override
  Future<List<OutboxItem>> outbox({String? destination, bool? private}) =>
    broken ? throw StateError('database closed') : super.outbox(destination: destination, private: private);
}

/// A store whose disk is full: it can not keep a voice note.
class _FullStore extends Store {
  _FullStore() : super(NativeDatabase.memory());

  @override
  Future<void> addVoiceNote(LocalNote note, {bool waitForPin = false}) => throw Exception('disk full');
}
