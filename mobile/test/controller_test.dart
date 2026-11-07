import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
import 'package:relay_app/sync/native.dart';
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

  RelayController controller({NativeBackground? native}) => RelayController(store: store, vault: KeyVault(storage), places: places,
    health: health, apiFor: server.api, signInClient: server.client, webAuth: webAuth.call, clock: () => clock,
    schedule: (on) async => scheduled.add(on), native: native, webhookFor: server.webhook, calendar: calendar);

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
      expect(await relay.setHealth(true), contains('Send my notes'));
      expect(await relay.setHistory(true), contains('Send my notes'));
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
      expect(await relay.setCalendar(true), contains('Send my notes'));
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
        'calendarsOff': [], 'mode': 'battery', 'place': 'server'});
      final back = Settings.decode(on.encode(), hasKey: false);
      expect([back.sending, back.health], [true, true]);
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
        'calendar': false, 'calendarsOff': [], 'mode': 'battery', 'place': 'server'});
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
        'calendar': false, 'calendarsOff': [], 'mode': 'battery', 'place': 'server'});
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
      expect(server.routes, ['key', 'notes', 'attachments', 'notes', 'attachments']);
      final uploads = [for (final request in server.requests) if (request.url.path.endsWith('attachments')) request];
      expect([for (final upload in uploads) upload.bodyBytes], [[9], [1, 2]]);
      final notes = sentNotes();
      expect(notes.first['attachments'],
        [{'id': uploads.first.headers['X-Attachment-Id'], 'name': 'old.pdf', 'type': 'application/pdf', 'size': 1}]);
      expect([for (final upload in uploads) upload.headers['X-Note-Client-Id']], [for (final note in notes) note['clientId']]);
      expect(relay.waiting, 0);
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
