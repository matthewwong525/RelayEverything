import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart' show KeychainAccessibility;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/outbox.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';

import 'fakes.dart';

final at = DateTime.fromMillisecondsSinceEpoch(1793797200000);

void main() {
  group('a key', () {
    test('is read from its QR code, scanned or pasted', () {
      final parsed = Connection.parse(' $code\n')!;
      expect([parsed.server, parsed.clientId, parsed.clientSecret], [connection.server, connection.clientId, connection.clientSecret]);
    });

    test('is refused when it is not whole, not https, or not Relay\'s', () {
      Map<String, Object?> with_(Map<String, Object?> change) =>
        {'relay': 1, 'server': 'https://relay.example.com', 'clientId': 'a', 'clientSecret': 'b', ...change};
      for (final text in ['', 'not json', '[1]', jsonEncode(with_({'relay': 2})), jsonEncode(with_({'server': 'http://relay.example.com'})),
        jsonEncode(with_({'server': 'https://relay.example.com/apps'})), jsonEncode(with_({'clientId': ''})), jsonEncode(with_({'clientSecret': 3}))]) {
        expect(Connection.parse(text), isNull, reason: text);
      }
    });

    test('is read in the page\'s form too: a rek_ key alone', () {
      final parsed = Connection.parse(pageCode)!;
      expect([parsed.server, parsed.key, parsed.clientId, parsed.clientSecret], [bearer.server, pageKey, null, null]);
      expect(parsed.headers, {'Authorization': 'Bearer $pageKey'});
      expect(parsed.withServer('https://other.example.com').key, pageKey);
    });

    test('is refused in the page\'s form when the key is bad, or both forms come at once', () {
      Map<String, Object?> with_(Map<String, Object?> change) => {'relay': 1, 'server': 'https://relay.example.com', 'key': pageKey, ...change};
      for (final text in [jsonEncode(with_({'key': ''})), jsonEncode(with_({'key': 3})), jsonEncode(with_({'key': 'rek_short'})),
        jsonEncode(with_({'key': '${pageKey}A'})), jsonEncode(with_({'key': pageKey.replaceFirst('rek_', 'rex_')})),
        jsonEncode(with_({'key': pageKey.replaceFirst('A', '+')})), jsonEncode(with_({'clientId': 'a', 'clientSecret': 'b'})),
        jsonEncode(with_({'clientSecret': 'b'})), jsonEncode(with_({'server': 'http://relay.example.com'})),
        jsonEncode({'relay': 1, 'server': 'https://relay.example.com'})]) {
        expect(Connection.parse(text), isNull, reason: text);
      }
    });

    test('keeps a server address as its origin alone', () {
      expect(Connection.serverOf('https://preview.example.com/'), 'https://preview.example.com');
      for (final value in [null, 3, 'preview.example.com', 'https://', 'https://x.example.com?a=1']) {
        expect(Connection.serverOf(value), isNull, reason: '$value');
      }
    });

    test('lives in the secure store, and is forgotten whole', () async {
      final storage = MemoryStorage();
      final vault = KeyVault(storage);
      expect(await vault.read(), isNull);
      await vault.save(connection);
      expect((await vault.read())!.clientSecret, connection.clientSecret);
      await vault.forget();
      expect(storage.values, isEmpty);
    });

    test('keeps a page key in the secure store, and a new key of either form replaces the other whole', () async {
      final storage = MemoryStorage();
      final vault = KeyVault(storage);
      await vault.save(connection);
      await vault.save(bearer);
      final read = (await vault.read())!;
      expect([read.server, read.key, read.clientId], [bearer.server, pageKey, null]);
      expect(storage.values.keys, unorderedEquals(['relay.server', 'relay.key']));
      await vault.save(connection);
      expect([(await vault.read())!.clientSecret, (await vault.read())!.key], [connection.clientSecret, null]);
      expect(storage.values.keys, unorderedEquals(['relay.server', 'relay.clientId', 'relay.clientSecret']));
      await vault.save(bearer);
      await vault.forget();
      expect(storage.values, isEmpty);
    });

    test('reads nothing from a store with a server but no whole key', () async {
      final storage = MemoryStorage()..values.addAll({'relay.server': 'https://relay.example.com', 'relay.clientId': 'a'});
      expect(await KeyVault(storage).read(), isNull);
    });

    test('opens after the first unlock on iPhone, so a wake on a locked phone can read it', () async {
      final storage = MemoryStorage();
      final vault = KeyVault(storage);
      await vault.save(bearer);
      await vault.read();
      await vault.forget();
      expect(storage.options.map((option) => option?.accessibility).toSet(), {KeychainAccessibility.first_unlock_this_device});
    });

    test('saves a key kept under the old Keychain access again, unchanged, with the new one', () async {
      final storage = MemoryStorage();
      // An earlier version saved with the plugin's default, open only while the phone is unlocked.
      storage.values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      storage.access.addAll({'relay.server': null, 'relay.key': null});
      final read = (await KeyVault(storage).upgrade())!;
      expect([read.server, read.key], [bearer.server, pageKey]);
      expect(storage.values, {'relay.server': bearer.server, 'relay.key': pageKey});
      expect(storage.access, {'relay.server': KeychainAccessibility.first_unlock_this_device,
        'relay.key': KeychainAccessibility.first_unlock_this_device});
      // No key: nothing to save, and nothing written.
      final empty = MemoryStorage();
      expect(await KeyVault(empty).upgrade(), isNull);
      expect(empty.values, isEmpty);
    });

    test('on iPhone moves an old key to the App Group, so the share card sends with it', () async {
      final storage = MemoryStorage()..values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      final vault = KeyVault(storage, true);
      expect((await vault.upgrade())!.key, pageKey);
      expect([storage.shared, storage.values], [{'relay.server': bearer.server, 'relay.key': pageKey}, isEmpty]);
      expect((await vault.read())!.key, pageKey);
      expect(storage.options.where((option) => option?.groupId != null).map((option) => option!.accountName).toSet(),
        {KeyVault.sharedService});
    });

    test('a stop part way through the move loses no key, and the next open finishes it', () async {
      final storage = MemoryStorage()..values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      storage.stopAfterWrites = 1;
      await expectLater(KeyVault(storage, true).upgrade(), throwsStateError);
      expect([storage.shared.keys, storage.values.length], [['relay.key'], 2]);
      expect((await KeyVault(storage, true).read())!.key, pageKey);
      storage.stopAfterWrites = null;
      expect((await KeyVault(storage, true).upgrade())!.key, pageKey);
      expect([storage.shared.length, storage.values], [2, isEmpty]);
      // Written whole but stopped before the delete: the next open deletes the old items.
      storage.values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      expect((await KeyVault(storage, true).upgrade())!.key, pageKey);
      expect([storage.shared.length, storage.values], [2, isEmpty]);
    });

    test('on iPhone saves to the App Group and forgets both groups', () async {
      final storage = MemoryStorage()..values.addAll({'relay.server': connection.server, 'relay.clientId': 'old'});
      final vault = KeyVault(storage, true);
      await vault.save(bearer);
      expect([storage.shared, storage.values], [{'relay.server': bearer.server, 'relay.key': pageKey}, isEmpty]);
      storage.values['relay.key'] = pageKey;
      await vault.forget();
      expect([storage.shared, storage.values], [isEmpty, isEmpty]);
    });

    test('a build with no App Group keeps the key in the app\'s own group', () async {
      final storage = MemoryStorage()..noGroup = true;
      final vault = KeyVault(storage, true);
      await vault.save(bearer);
      expect([storage.values.keys, storage.shared], [unorderedEquals(['relay.server', 'relay.key']), isEmpty]);
      expect((await vault.read())!.key, pageKey);
      expect((await vault.upgrade())!.key, pageKey);
      await vault.forget();
      expect(storage.values, isEmpty);
    });

    test('Android has one home and never moves the key', () async {
      final storage = MemoryStorage()..values.addAll({'relay.server': bearer.server, 'relay.key': pageKey});
      final vault = KeyVault(storage, false);
      expect((await vault.upgrade())!.key, pageKey);
      await vault.save(bearer);
      await vault.read();
      expect([storage.shared, storage.values.length], [isEmpty, 2]);
      expect(storage.options.where((option) => option?.groupId != null), isEmpty);
    });
  });

  group('a webhook', () {
    test('takes an https address, a home one too, and refuses others with a reason', () {
      for (final good in ['https://db.example.com/relay', ' https://192.168.1.20:8443/in ', 'https://nas.local/hook']) {
        expect(Webhook.addressProblem(good), isNull, reason: good);
      }
      expect([Webhook.addressProblem('http://db.example.com'), Webhook.addressProblem('db.example.com'),
        Webhook.addressProblem('https://me:pw@db.example.com'), Webhook.addressProblem('https://')], [
        'The address must start with https://.', 'The address must start with https://.',
        'Take the user name and password out of the address.', 'Enter the whole address, such as https://db.example.com/relay.']);
      expect(hook.host, 'db.example.com');
    });

    test('takes a whsec_ secret of 16 to 64 bytes, as Standard Webhooks libraries do', () {
      expect([Webhook.secretProblem(fixtureSecret), Webhook.secretProblem(' $fixtureSecret\n')], [isNull, isNull]);
      for (final bad in ['', 'cmVsYXk=', 'whsec_', 'whsec_not base64!', 'whsec_${'A' * 20}', 'whsec_${'A' * 100}']) {
        expect(Webhook.secretProblem(bad), 'The secret must be whsec_ and then base64, as your receiver shows it.', reason: bad);
      }
    });

    test('lives in the app\'s own secure group, apart from the key, and is forgotten alone', () async {
      final storage = MemoryStorage();
      final vault = KeyVault(storage);
      expect(await vault.readWebhook(), isNull);
      await vault.save(bearer);
      await vault.saveWebhook(hook);
      expect([(await vault.readWebhook())!.address, (await vault.readWebhook())!.secret], [hook.address, hook.secret]);
      expect(storage.values.keys, containsAll(['relay.webhook.address', 'relay.webhook.secret']));
      expect(storage.shared.keys.where((name) => name.contains('webhook')), isEmpty);
      await vault.forget();
      expect(await vault.readWebhook(), isNotNull);
      await vault.forgetWebhook();
      expect([await vault.readWebhook(), storage.values.keys.where((name) => name.contains('webhook'))], [isNull, isEmpty]);
    });
  });

  group('the API', () {
    test('sends the key in both Access headers, and the body as JSON', () async {
      final server = FakeServer();
      expect(await server.api(connection).post('notes', {'text': 'hi'}), {'added': 1});
      final request = server.requests.single;
      expect(request.url.toString(), 'https://relay.example.com/apps/relay/api/notes');
      expect(request.headers['CF-Access-Client-Id'], 'phone.access');
      expect(request.headers['CF-Access-Client-Secret'], 'secret-value');
      expect(request.headers['Authorization'], isNull);
      expect(jsonDecode(request.body), {'text': 'hi'});
    });

    test('sends a page key as Authorization: Bearer, and no Access headers', () async {
      final server = FakeServer();
      expect(await server.api(bearer).post('notes', {'text': 'hi'}), {'added': 1});
      expect(await server.api(bearer).key(), 'Android phone');
      for (final request in server.requests) {
        expect(request.headers['Authorization'], 'Bearer $pageKey');
        expect(request.headers.keys.where((name) => name.toLowerCase().startsWith('cf-access')), isEmpty);
      }
    });

    test('checks a key with GET key, which gives the device name and no data', () async {
      final server = FakeServer((_) => FakeServer.json({'device': 'iPhone'}));
      expect(await server.api(connection).key(), 'iPhone');
      final request = server.requests.single;
      expect([request.method, request.url.toString()], ['GET', 'https://relay.example.com/apps/relay/api/key']);
      expect(request.headers['CF-Access-Client-Id'], 'phone.access');
      for (final status in [401, 403]) {
        await expectLater(FakeServer((_) => FakeServer.json({}, status)).api(connection).key(),
          throwsA(isA<ApiException>().having((error) => error.failure, 'failure', Failure.refused)), reason: '$status');
      }
    });

    test('reads no data: no code calls the timeline or audio routes, and the GETs are the key check and the names', () {
      final sources = [
        for (final file in Directory('lib').listSync(recursive: true)) if (file is File && file.path.endsWith('.dart')) file.readAsStringSync(),
      ].join('\n');
      expect([for (final call in RegExp(r"_client\.get\(_uri\('(\w+)'").allMatches(sources)) call[1]], ['key', 'connections']);
      expect(sources, isNot(matches(RegExp(r"api/(timeline|audio)|_uri\('(timeline|audio)"))));
    });

    test('names each failure: a refused key, a body turned down, or no answer', () async {
      Future<Failure?> failureOf(http.Response response) async {
        try {
          await FakeServer((_) => response).api(connection).post('notes', {});
          return null;
        } on ApiException catch (error) {
          return error.failure;
        }
      }
      expect(await failureOf(http.Response('', 401)), Failure.refused);
      expect(await failureOf(http.Response('', 403)), Failure.refused);
      expect(await failureOf(http.Response('', 302)), Failure.refused);
      expect(await failureOf(http.Response('<html>Sign in</html>', 200, headers: {'content-type': 'text/html'})), Failure.refused);
      expect(await failureOf(FakeServer.json({}, 400)), Failure.rejected);
      expect(await failureOf(FakeServer.json({}, 413)), Failure.rejected);
      expect(await failureOf(FakeServer.json({}, 503)), Failure.offline);
      final api = RelayApi(connection, MockClient((_) => throw const SocketException('no signal')));
      await expectLater(api.key(), throwsA(isA<ApiException>().having((error) => error.failure, 'failure', Failure.offline)));
      expect(const ApiException(Failure.offline, 503).toString(), contains('503'));
    });

    test('uploads a photo as a multipart body: its fields, and the JPEG with its content type', () async {
      final server = FakeServer((_) => FakeServer.json({'ok': true, 'added': 1}));
      final jpeg = jpegOf(1600, 1200);
      expect(await server.api(bearer).multipart('photos', {'clientId': 'photo-0001', 'takenAt': '1793797200000'},
        file: 'photo', bytes: jpeg, filename: 'photo-0001.jpg', contentType: 'image/jpeg'), {'ok': true, 'added': 1});
      final request = server.requests.single;
      expect([request.method, request.url.toString()], ['POST', 'https://relay.example.com/apps/relay/api/photos']);
      expect(request.headers['Authorization'], 'Bearer $pageKey');
      expect(request.headers['content-type'], startsWith('multipart/form-data; boundary='));
      final parts = formParts(request);
      expect(parts.keys, ['clientId', 'takenAt', 'photo']);
      expect([parts['clientId'], parts['takenAt']], [(null, 'photo-0001'), (null, '1793797200000')]);
      expect(parts['photo']!.$1, 'image/jpeg');
      expect(latin1.encode(parts['photo']!.$2), jpeg);
    });

    test('names an upload\'s failure the same way as a JSON body\'s', () async {
      Future<Failure?> failureOf(http.Response Function(http.Request) answer) async {
        try {
          await FakeServer(answer).api(connection).multipart('photos', {'clientId': 'photo-0001'}, file: 'photo', bytes: jpegOf(10, 10),
            filename: 'photo-0001.jpg', contentType: 'image/jpeg');
          return null;
        } on ApiException catch (error) {
          return error.failure;
        }
      }
      expect(await failureOf((_) => FakeServer.json({'ok': true, 'added': 0})), isNull);
      expect(await failureOf((_) => FakeServer.json({'error': 'not a JPEG'}, 400)), Failure.rejected);
      expect(await failureOf((_) => FakeServer.json({}, 413)), Failure.rejected);
      expect(await failureOf((_) => FakeServer.json({}, 403)), Failure.refused);
      expect(await failureOf((_) => FakeServer.json({}, 401)), Failure.refused);
      expect(await failureOf((_) => FakeServer.json({}, 502)), Failure.offline);
      final api = RelayApi(connection, MockClient((_) => throw const SocketException('no signal')));
      await expectLater(api.multipart('photos', {}, file: 'photo', bytes: [1], filename: 'x.jpg', contentType: 'image/jpeg'),
        throwsA(isA<ApiException>().having((error) => error.failure, 'failure', Failure.offline)));
    });
  });

  group('the store and outbox', () {
    late Store store;
    setUp(() => store = memoryStore());
    tearDown(() => store.close());

    LocalNote note(String id) => LocalNote(clientId: id, text: 'Note $id', createdAt: DateTime.fromMillisecondsSinceEpoch(1793797200000));

    test('keeps a note with no upload while sending is off, and queues the earlier ones oldest first on request', () async {
      LocalNote at_(String id, int minute) =>
        LocalNote(clientId: id, text: 'Note $id', createdAt: at.add(Duration(minutes: minute)));
      await store.addNote(at_('late', 2));
      await store.addNote(at_('early', 0));
      await store.addNote(at_('middle', 1));
      expect([await store.earlierCount(), (await store.outbox()).length, await store.waiting()], [3, 0, 0]);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.queued, kept.sentAt)],
        [('late', false, null), ('middle', false, null), ('early', false, null)]);
      await store.queueEarlier();
      expect([for (final item in await store.outbox()) item.body['clientId']], ['early', 'middle', 'late']);
      expect(await store.earlierCount(), 0);
      await flush(store, FakeServer().api(connection), clock: () => at);
      expect([for (final kept in await store.notes()) kept.sentAt], [at, at, at]);
    });

    test('drops waiting health, location and calendar, and keeps note uploads', () async {
      await store.addNote(note('note-0001'), send: true);
      await store.enqueue('health', {'samples': []});
      await store.queueCalendar([{'events': [{'key': 'k'}], 'removed': []}], {'k': 'hash'}, const []);
      await store.addPoint(Pin(at: at, lat: 1, lon: 1, accuracy: 1));
      await store.queuePoints();
      await store.addPoint(Pin(at: at.add(const Duration(minutes: 1)), lat: 1, lon: 1, accuracy: 1));
      await store.dropReadings();
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      expect(await store.calendarSent(), isEmpty);
      await store.queuePoints();
      expect(await store.waiting(), 1);
    });

    test('records when health and points last landed, and counts what waits of each', () async {
      expect([await store.sentAt(sentHealth), await store.sentAt(sentPoints), await store.waitingReadings(), await store.waitingPoints()],
        [null, null, 0, 0]);
      await store.enqueue('health', {'samples': [{}, {}, {}]});
      await store.addPoint(Pin(at: at, lat: 1, lon: 1, accuracy: 1));
      await store.queuePoints();
      await store.addPoint(Pin(at: at.add(const Duration(minutes: 1)), lat: 1, lon: 1, accuracy: 1));
      expect([await store.waitingReadings(), await store.waitingPoints()], [3, 2]);
      final server = FakeServer((request) => request.url.path.endsWith('locations') ? FakeServer.json({}, 503) : FakeServer.ok(request));
      await flush(store, server.api(connection), clock: () => at);
      expect([await store.sentAt(sentHealth), await store.sentAt(sentPoints), await store.waitingReadings()], [at, null, 0]);
      server.answer = FakeServer.ok;
      await flush(store, server.api(connection), clock: () => at.add(const Duration(hours: 1)));
      expect([await store.sentAt(sentPoints), await store.waitingPoints()], [at.add(const Duration(hours: 1)), 1]);
    });

    test('keeps each upload under its destination, and queues to the place sending is set to', () async {
      await store.enqueue('notes', {'clientId': 'a'});
      await store.enqueue('notes', {'clientId': 'b'}, destination: ownWebhook);
      expect([for (final item in await store.outbox()) (item.body['clientId'], item.destination)],
        [('a', relayServer), ('b', ownWebhook)]);
      expect([for (final item in await store.outbox(destination: ownWebhook)) item.body['clientId']], ['b']);
      expect(await store.destination(), relayServer);
      await store.moveOutbox(ownWebhook);
      await store.enqueue('notes', {'clientId': 'c'});
      expect([await store.destination(), {for (final item in await store.outbox()) item.destination}], [ownWebhook, {ownWebhook}]);
      await store.moveOutbox(relayServer);
      expect({for (final item in await store.outbox()) item.destination}, {relayServer});
    });

    test('gives each point an id once, fills ids in points queued before ids, and gives samples none', () async {
      await store.enqueue('health', {'samples': [{'type': 'steps'}]});
      await store.enqueue('locations', {'points': [{'lat': 1}]});
      await store.queueSamples([for (var i = 0; i < 501; i++) {'type': 'steps'}]);
      await store.addPoint(Pin(at: at, lat: 1, lon: 1, accuracy: 1));
      await store.queuePoints();
      await store.moveOutbox(ownWebhook);
      final outbox = await store.outbox();
      final points = [for (final item in outbox) ...?item.body['points'] as List?];
      final samples = [for (final item in outbox) ...?item.body['samples'] as List?];
      expect([for (final point in points) (point as Map)['id']], unorderedEquals([1, 2]));
      expect([samples.length, samples.every((sample) => !(sample as Map).containsKey('id'))], [502, true]);
      expect([for (final item in outbox) item.route], ['health', 'locations', 'health', 'health', 'locations']);
      final id = await store.installId();
      expect([id, await store.installId()], [matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')), id]);
    });

    test('keeps a typed note as waiting until its upload lands, in order', () async {
      await store.addNote(note('note-0001'), send: true);
      await store.addNote(note('note-0002'), send: true);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.queued)], unorderedEquals([('note-0001', true), ('note-0002', true)]));
      final server = FakeServer();
      final result = await flush(store, server.api(connection));
      expect([result.sent, result.dropped, result.failure], [2, 0, null]);
      expect([for (final request in server.requests) jsonDecode(request.body)['clientId']], ['note-0001', 'note-0002']);
      expect(jsonDecode(server.requests.first.body), isNot(contains('place')));
      expect([for (final kept in await store.notes()) kept.sentAt != null], [true, true]);
      expect(await store.waiting(), 0);
    });

    test('stops at the first upload that can not land, and keeps it and the rest', () async {
      await store.addNote(note('note-0001'), send: true);
      await store.addNote(note('note-0002'), send: true);
      for (final failure in [(503, Failure.offline), (401, Failure.refused)]) {
        final server = FakeServer((_) => FakeServer.json({}, failure.$1));
        final result = await flush(store, server.api(connection));
        expect([result.sent, result.failure, server.requests.length], [0, failure.$2, 1]);
        expect(await store.waiting(), 2);
      }
    });

    test('drops a body the server turns down, so it holds back nothing', () async {
      await store.addNote(note('note-0001'), send: true);
      await store.enqueue('health', {'samples': []});
      final server = FakeServer((request) => request.url.path.endsWith('notes') ? FakeServer.json({}, 400) : FakeServer.ok(request));
      final result = await flush(store, server.api(connection));
      expect([result.sent, result.dropped], [1, 1]);
      expect(await store.waiting(), 0);
    });

    test('sends location points once each, 500 to a batch, oldest first', () async {
      for (var i = 0; i < 1001; i++) {
        await store.addPoint(Pin(at: DateTime.fromMillisecondsSinceEpoch(1793797200000 + i * 1000), lat: 43.6, lon: -79.3, accuracy: 10));
      }
      await store.addPoint(Pin(at: at, lat: 1, lon: 1, accuracy: 1));
      await store.queuePoints();
      final batches = [for (final item in await store.outbox()) (item.body['points'] as List)];
      expect([for (final batch in batches) batch.length], [500, 500, 1]);
      expect((batches.first.first as Map)['at'], 1793797200000);
      expect((batches.first.first as Map).containsKey('place'), isFalse);
      await store.queuePoints();
      expect(await store.waiting(), 3);
    });

    test('upgrades a first-version phone: sent notes keep a send time, and a note that waited for its pin is queued', () async {
      // This test opens a second store beside the group's on purpose.
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          'CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent INTEGER NOT NULL DEFAULT 0, '
            'queued INTEGER NOT NULL DEFAULT 1)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        ]) {
          db.execute(statement);
        }
        String body(String id) => jsonEncode(note(id).toJson());
        db.execute('INSERT INTO notes VALUES (?, ?, ?, 1, 1), (?, ?, ?, 0, 1), (?, ?, ?, 0, 0)',
          ['sent', body('sent'), 1, 'queued', body('queued'), 2, 'pinning', body('pinning'), 3]);
        db.execute("INSERT INTO outbox (route, body, created_at) VALUES ('notes', ?, 2)", [body('queued')]);
        db.execute('PRAGMA user_version = 2');
      }));
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) (kept.clientId, kept.sentAt?.millisecondsSinceEpoch, kept.queued)],
        [('pinning', null, true), ('queued', null, true), ('sent', 1, true)]);
      expect([for (final item in await old.outbox()) item.body['clientId']], ['queued', 'pinning']);
      expect(await old.earlierCount(), 0);
    });

    test('upgrades a phone from before voice notes: its notes read as typed, with their uploads', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
            'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
            'queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        ]) {
          db.execute(statement);
        }
        String body(String id) => jsonEncode(note(id).toJson());
        db.execute('INSERT INTO notes VALUES (?, ?, ?, 5, 1, 0), (?, ?, ?, NULL, 0, 0)',
          ['sent', body('sent'), 1, 'local', body('local'), 2]);
        db.execute('PRAGMA user_version = 3');
      }));
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) (kept.clientId, kept.kind, kept.audioPath, kept.durationMs, kept.wordsPending)],
        [('local', NoteKind.typed, null, null, false), ('sent', NoteKind.typed, null, null, false)]);
      expect(await old.earlierCount(), 1);
      expect(await old.pendingWords(), isEmpty);
    });

    test('keeps a voice note with no words and no upload until its words land', () async {
      final voice = LocalNote(clientId: 'v', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/v.wav', durationMs: 12000);
      await store.addVoiceNote(voice);
      final kept = (await store.notes()).single;
      expect([kept.kind, kept.audioPath, kept.durationMs, kept.wordsPending, kept.text], [NoteKind.voice, 'voice/v.wav', 12000, true, '']);
      // Not an earlier note: *Send them* can not send it with no words.
      expect([await store.earlierCount(), (await store.outbox()).length], [0, 0]);
      expect([for (final note in await store.pendingWords()) note.clientId], ['v']);
      expect(await store.setWords('v', 'Order more switches', send: true), isTrue);
      expect(await store.setWords('v', 'Again', send: true), isFalse);
      // The upload is a typed note's body: the words, never the recording.
      expect((await store.outbox()).single.body, {'clientId': 'v', 'text': 'Order more switches', 'createdAt': at.millisecondsSinceEpoch});
      expect([(await store.notes()).single.wordsPending, (await store.notes()).single.queued], [false, true]);
      expect(await store.pendingWords(), isEmpty);
    });

    test('a voice note with typed words puts them first, and goes once it has its words', () async {
      await store.addVoiceNote(LocalNote(clientId: 'v', text: 'Note @ 7:07 PM', createdAt: at, kind: NoteKind.voice,
        audioPath: 'voice/v.wav'));
      expect(await store.outbox(), isEmpty);
      expect(await store.setWords('v', 'Call the plumber', send: true), isTrue);
      expect((await store.outbox()).single.body,
        {'clientId': 'v', 'text': 'Note @ 7:07 PM\nCall the plumber', 'createdAt': at.millisecondsSinceEpoch});
    });

    test('a voice note given words with sending off stays only here, and counts as earlier', () async {
      await store.addVoiceNote(LocalNote(clientId: 'v', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/v.wav'));
      expect(await store.setWords('v', 'Words', send: false), isTrue);
      expect([await store.earlierCount(), (await store.outbox()).length], [1, 0]);
      await store.addVoiceNote(LocalNote(clientId: 'silent', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/silent.wav'));
      await store.dropNote('silent');
      expect([for (final note in await store.notes()) note.clientId], ['v']);
    });

    QueuedPhoto photo(String id, int minute, {double? lat, double? lon}) => QueuedPhoto(clientId: id, assetId: 'asset-$id',
      takenAt: at.add(Duration(minutes: minute)), lat: lat, lon: lon, width: 1600, height: 1200, path: photoPathOf(id));

    Future<File> copyOf(QueuedPhoto photo) async {
      final file = await store.photoFile(photo.path);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(jpegOf(photo.width, photo.height));
      return file;
    }

    test('keeps photos in their own queue, oldest first, and a photo done loses its row and its copy', () async {
      final late = photo('late', 5), early = photo('early', 1, lat: 43.65, lon: -79.38);
      final files = [await copyOf(late), await copyOf(early)];
      await store.addPhoto(late);
      await store.addPhoto(early);
      await store.addNote(note('note-0001'), send: true);
      final waiting = await store.waitingPhotos();
      expect([for (final kept in waiting) kept.clientId], ['early', 'late']);
      expect([waiting.first.assetId, waiting.first.takenAt, waiting.first.lat, waiting.first.lon, waiting.first.width,
        waiting.first.height, waiting.first.path], ['asset-early', at.add(const Duration(minutes: 1)), 43.65, -79.38, 1600, 1200,
        'photos/early.jpg']);
      expect(waiting.first.fields, {'clientId': 'early', 'takenAt': '${at.millisecondsSinceEpoch + 60000}', 'lat': '43.65', 'lon': '-79.38'});
      expect(waiting.last.fields.keys, ['clientId', 'takenAt']);
      // The outbox is apart: a photo waiting for Wi-Fi holds back no note.
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      await store.photoDone('early');
      expect([for (final kept in await store.waitingPhotos()) kept.clientId], ['late']);
      expect([files.first.existsSync(), files.last.existsSync()], [true, false]);
    });

    test('drops every waiting photo with its copy, and keeps notes and their uploads', () async {
      final files = [for (final (index, id) in ['a', 'b'].indexed) await copyOf(photo(id, index))];
      for (final (index, id) in ['a', 'b'].indexed) {
        await store.addPhoto(photo(id, index));
      }
      await store.addNote(note('note-0001'), send: true);
      await store.dropPhotos();
      expect([await store.waitingPhotos(), [for (final file in files) file.existsSync()]], [isEmpty, [false, false]]);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      // A photo whose copy is gone already is dropped too.
      await store.addPhoto(photo('c', 3));
      await store.dropPhotos();
      expect(await store.waitingPhotos(), isEmpty);
    });

    group('files', () {
      late Directory folder;
      setUp(() {
        folder = tempFolder();
        Directory('${folder.path}/attachments').createSync();
      });

      Attachment kept(String id, String name, String type, List<int> bytes) {
        File('${folder.path}/attachments/$id').writeAsBytesSync(bytes);
        return Attachment(id: id, name: name, type: type, size: bytes.length, path: 'attachments/$id');
      }

      Future<FlushResult> send(FakeServer server) =>
        flush(store, server.api(bearer), clock: () => at, folder: () async => folder);

      test('a note lists its files, and each file goes after its note as its own upload', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Receipt for the desk lamp', createdAt: at, attachments: [
          kept('f1', 'receipt.jpg', 'image/jpeg', [1, 2, 3, 4]),
          kept('f2', 'warranty.pdf', 'application/pdf', [5, 6]),
        ]), send: true);
        expect([for (final item in await store.outbox()) item.route], ['notes', 'attachment', 'attachment']);
        expect((await store.outbox()).first.body['attachments'], [
          {'id': 'f1', 'name': 'receipt.jpg', 'type': 'image/jpeg', 'size': 4},
          {'id': 'f2', 'name': 'warranty.pdf', 'type': 'application/pdf', 'size': 2},
        ]);
        final server = FakeServer();
        final result = await send(server);
        expect([result.sent, result.dropped, result.failure], [3, 0, null]);
        expect(server.routes, ['notes', 'attachments', 'attachments']);
        final upload = server.requests[1];
        expect([upload.method, upload.url.toString()], ['POST', 'https://relay.example.com/apps/relay/api/attachments']);
        expect([upload.headers['Authorization'], upload.headers['X-Note-Client-Id'], upload.headers['X-Attachment-Id'],
          upload.headers['Content-Type']], ['Bearer $pageKey', 'n1', 'f1', 'image/jpeg']);
        expect(upload.bodyBytes, [1, 2, 3, 4]);
        expect(server.requests[2].bodyBytes, [5, 6]);
        final note = (await store.notes()).single;
        expect([note.sentAt, for (final file in note.attachments) file.sentAt], [at, at, at]);
        expect(await store.waiting(), 0);
      });

      test('a note without files sends the body it sent before', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Plain', createdAt: at), send: true);
        expect((await store.outbox()).single.body, {'clientId': 'n1', 'text': 'Plain', 'createdAt': at.millisecondsSinceEpoch});
      });

      test('a file the server turns down, or one no longer on the phone, is dropped; its note stays sent', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Two files', createdAt: at, attachments: [
          kept('f1', 'a.jpg', 'image/jpeg', [1]),
          const Attachment(id: 'gone', name: 'b.pdf', type: 'application/pdf', size: 1, path: 'attachments/gone'),
        ]), send: true);
        await store.addNote(LocalNote(clientId: 'n2', text: 'After', createdAt: at.add(const Duration(minutes: 1))), send: true);
        for (final status in [404, 413, 400]) {
          expect(await FakeServer((_) => FakeServer.json({}, status)).api(bearer)
            .upload(noteClientId: 'n1', id: 'f1', type: 'image/jpeg', bytes: [1])
            .then<Failure?>((_) => null, onError: (Object error) => (error as ApiException).failure), Failure.rejected, reason: '$status');
        }
        final server = FakeServer((request) =>
          request.url.path.endsWith('attachments') ? FakeServer.json({'error': 'This file is not on its note.'}, 404) : FakeServer.ok(request));
        final result = await send(server);
        expect([result.sent, result.dropped, result.failure], [2, 2, null]);
        expect(server.routes, ['notes', 'attachments', 'notes']);
        expect([for (final note in await store.notes()) note.sentAt], [at, at]);
        expect(await store.waiting(), 0);
      });

      test('a server older than files gets the note once more without its list, and drops the files', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'With a file', createdAt: at, attachments: [
          kept('f1', 'a.jpg', 'image/jpeg', [1]),
        ]), send: true);
        // The old server refuses unknown note fields with 400 and has no file route.
        final server = FakeServer((request) {
          if (request.url.path.endsWith('attachments')) return FakeServer.json({'error': 'Not found'}, 404);
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return body.containsKey('attachments') ? FakeServer.json({'error': 'Unrecognized key'}, 400) : FakeServer.ok(request);
        });
        final result = await send(server);
        expect([result.sent, result.dropped, result.failure], [1, 1, null]);
        expect(server.routes, ['notes', 'notes', 'attachments']);
        expect(jsonDecode(server.requests[1].body), {'clientId': 'n1', 'text': 'With a file', 'createdAt': at.millisecondsSinceEpoch});
        expect((await store.notes()).single.sentAt, at);
        expect(await store.waiting(), 0);
      });

      test('a note with files that the server turns down twice is dropped after two tries', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Bad', createdAt: at, attachments: [
          kept('f1', 'a.jpg', 'image/jpeg', [1]),
        ]), send: true);
        final server = FakeServer((request) => FakeServer.json({}, 400));
        final result = await send(server);
        expect([result.sent, result.dropped, result.failure], [0, 2, null]);
        expect(server.routes, ['notes', 'notes', 'attachments']);
      });

      test('a 404 on a note still means the server could not be reached, so the note waits', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Waits', createdAt: at), send: true);
        final result = await send(FakeServer((_) => FakeServer.json({}, 404)));
        expect([result.sent, result.failure], [0, Failure.offline]);
        expect(await store.waiting(), 1);
      });

      test('a file whose answer was lost goes again with the same id, and is sent once it lands', () async {
        await store.addNote(LocalNote(clientId: 'n1', text: 'Photo', createdAt: at,
          attachments: [kept('f1', 'a.jpg', 'image/jpeg', [1])]), send: true);
        final lost = FakeServer((request) =>
          request.url.path.endsWith('attachments') ? FakeServer.json({}, 503) : FakeServer.ok(request));
        expect((await send(lost)).failure, Failure.offline);
        expect([for (final item in await store.outbox()) item.route], ['attachment']);
        final server = FakeServer((_) => FakeServer.json({'ok': true, 'added': false}));
        expect((await send(server)).failure, isNull);
        expect([lost.requests.last.headers['X-Attachment-Id'], server.requests.single.headers['X-Attachment-Id']], ['f1', 'f1']);
        expect((await store.notes()).single.attachments.single.sentAt, at);
      });

      test('Send them queues an earlier note with its files, and a new note goes with its files', () async {
        await store.addNote(LocalNote(clientId: 'early', text: 'Earlier', createdAt: at,
          attachments: [kept('f1', 'old.pdf', 'application/pdf', [9])]));
        expect([await store.earlierCount(), (await store.outbox()).length], [1, 0]);
        await store.queueEarlier();
        await store.addNote(LocalNote(clientId: 'new', text: 'New', createdAt: at.add(const Duration(minutes: 1)),
          attachments: [kept('f2', 'new.jpg', 'image/jpeg', [8])]), send: true);
        final outbox = await store.outbox();
        expect([for (final item in outbox) (item.route, item.body['clientId'] ?? item.body['id'])],
          [('notes', 'early'), ('attachment', 'f1'), ('notes', 'new'), ('attachment', 'f2')]);
        expect(outbox[2].body['attachments'], [{'id': 'f2', 'name': 'new.jpg', 'type': 'image/jpeg', 'size': 1}]);
        expect(outbox[1].body, {'noteClientId': 'early', 'id': 'f1', 'path': 'attachments/f1', 'name': 'old.pdf', 'type': 'application/pdf'});
      });
    });

    test('upgrades a phone from before files: every note stays, with no files, and new notes take files', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
            'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
            "queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'typed', "
            'audio_path TEXT, duration_ms INTEGER, words_pending INTEGER NOT NULL DEFAULT 0)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        ]) {
          db.execute(statement);
        }
        String body(String id) => jsonEncode(note(id).toJson());
        db.execute("INSERT INTO notes (client_id, body, created_at, sent_at, queued, kind, audio_path, duration_ms) VALUES "
          "(?, ?, 1, 5, 1, 'typed', NULL, NULL), (?, ?, 2, NULL, 0, 'typed', NULL, NULL), (?, ?, 3, NULL, 1, 'voice', 'voice/v.wav', 4000)",
          ['sent', body('sent'), 'local', body('local'), 'voice', body('voice')]);
        db.execute("INSERT INTO outbox (route, body, created_at) VALUES ('notes', ?, 3)", [body('voice')]);
        db.execute('PRAGMA user_version = 4');
      }));
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) (kept.clientId, kept.kind, kept.sentAt != null, kept.attachments.length)],
        [('voice', NoteKind.voice, false, 0), ('local', NoteKind.typed, false, 0), ('sent', NoteKind.typed, true, 0)]);
      expect([for (final item in await old.outbox()) item.route], ['notes']);
      expect(await old.earlierCount(), 1);
      await old.addNote(LocalNote(clientId: 'new', text: 'With a file', createdAt: at.add(const Duration(days: 1)),
        attachments: const [Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f1')]));
      expect([for (final file in await old.attachmentsOf('new')) file.name], ['a.pdf']);
    });

    test('upgrades a phone from before the calendar: notes and uploads stay, and the calendar can be sent', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
            'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
            "queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'typed', "
            'audio_path TEXT, duration_ms INTEGER, words_pending INTEGER NOT NULL DEFAULT 0)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          'CREATE TABLE attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, size INTEGER, '
            'path TEXT, sent_at INTEGER)',
        ]) {
          db.execute(statement);
        }
        db.execute('INSERT INTO notes (client_id, body, created_at, queued) VALUES (?, ?, 1, 1)',
          ['kept', jsonEncode(note('kept').toJson())]);
        db.execute("INSERT INTO outbox (route, body, created_at) VALUES ('health', '{\"samples\":[{}]}', 2)");
        db.execute("INSERT INTO state (key, value) VALUES ('health.since', '5')");
        db.execute('PRAGMA user_version = 5');
      }));
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) kept.clientId], ['kept']);
      expect([await old.waitingReadings(), await old.get('health.since'), await old.calendarSent()], [1, '5', isEmpty]);
      await old.queueCalendar([{'events': [{'key': 'k'}], 'removed': ['gone']}], {'k': 'hash'}, const ['gone']);
      expect([await old.waitingEvents(), await old.calendarSent()], [2, {'k': 'hash'}]);
    });

    test('upgrades a phone from before photos: its notes and uploads stay, and photos can wait', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final folder = tempFolder();
      final old = Store(NativeDatabase.memory(setup: (db) {
        for (final statement in [
          "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
            'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
          'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
            "queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'typed', "
            'audio_path TEXT, duration_ms INTEGER, words_pending INTEGER NOT NULL DEFAULT 0)',
          'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
          'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          'CREATE TABLE attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, size INTEGER, '
            'path TEXT, sent_at INTEGER)',
          'CREATE TABLE calendar_sent (key TEXT PRIMARY KEY, hash TEXT NOT NULL)',
        ]) {
          db.execute(statement);
        }
        final body = jsonEncode(note('queued').toJson());
        db.execute('INSERT INTO notes (client_id, body, created_at, queued) VALUES (?, ?, 1, 1)', ['queued', body]);
        db.execute("INSERT INTO outbox (route, body, created_at) VALUES ('notes', ?, 1)", [body]);
        db.execute("INSERT INTO state VALUES ('settings', '{\"sending\":true}')");
        db.execute("INSERT INTO calendar_sent VALUES ('k', 'hash')");
        db.execute('PRAGMA user_version = 6');
      }), folder: () async => folder);
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) (kept.clientId, kept.queued)], [('queued', true)]);
      expect([for (final item in await old.outbox()) item.body['clientId']], ['queued']);
      expect([await old.get('settings'), await old.calendarSent()], ['{"sending":true}', {'k': 'hash'}]);
      expect(await old.waitingPhotos(), isEmpty);
      final file = File('${folder.path}/photos/p.jpg');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(jpegOf(4, 3));
      await old.addPhoto(QueuedPhoto(clientId: 'p', assetId: 'asset-p', takenAt: at, width: 4, height: 3, path: photoPathOf('p')));
      expect([for (final kept in await old.waitingPhotos()) (kept.clientId, kept.lat, kept.width)], [('p', null, 4)]);
      await old.dropPhotos();
      expect([await old.waitingPhotos(), file.existsSync()], [isEmpty, false]);
    });

    group('upgrades a phone whose notes kept a place', () {
      Map<String, Object?> placed(String id, int minute) => {'clientId': id, 'text': 'Note $id',
        'createdAt': at.add(Duration(minutes: minute)).millisecondsSinceEpoch, 'lat': 43.65, 'lon': -79.38, 'accuracy': 12.0,
        'place': 'King St W'};

      /// A version 11 store with a sent and an unsent placed note, and a note that waits for its pin.
      Future<Store> upgraded({required bool history}) async {
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
        final file = File('${tempFolder().path}/relay.db');
        final made = Store(NativeDatabase(file));
        await made.get('x');
        await made.close();
        final old = Store(NativeDatabase(file, setup: (db) {
          if (db.userVersion != 13) return;
          // Version 13 added the source column.
          db.execute('ALTER TABLE notes DROP COLUMN source');
          db.execute('INSERT INTO state VALUES (?, ?)',
            [settingsKey, jsonEncode({'sending': true, 'history': history, 'locationSend': 'points'})]);
          db.execute('INSERT INTO notes (client_id, body, created_at, sent_at, queued, pinning) VALUES '
            '(?, ?, 1, 5, 1, 0), (?, ?, 2, NULL, 1, 0), (?, ?, 3, NULL, 0, 1)', [
            'sent', jsonEncode(placed('sent', 0)), 'unsent', jsonEncode(placed('unsent', 1)),
            'pinning', jsonEncode(note('pinning').toJson())]);
          db.execute("INSERT INTO outbox (route, body, created_at) VALUES ('notes', ?, 2)", [jsonEncode(placed('unsent', 1))]);
          db.execute('PRAGMA user_version = 11');
        }));
        addTearDown(old.close);
        return old;
      }

      test('with location history on, an unsent note\'s place becomes a point at its time, and a sent note\'s does not',
        () async {
        final old = await upgraded(history: true);
        expect(await old.waitingPoints(), 1);
        await old.queuePoints();
        final point = (await old.outbox()).firstWhere((item) => item.route == 'locations').body['points'].single as Map;
        expect([point['at'], point['lat'], point['place']], [at.add(const Duration(minutes: 1)).millisecondsSinceEpoch, 43.65,
          'King St W']);
      });

      test('with location history off, the place is dropped; every body loses its place, and the waiting note is queued',
        () async {
        final old = await upgraded(history: false);
        expect(await old.waitingPoints(), 0);
        final notes = [for (final item in await old.outbox()) if (item.route == 'notes') item.body];
        expect([for (final body in notes) (body['clientId'], body.containsKey('lat'), body.containsKey('place'))],
          [('unsent', false, false), ('pinning', false, false)]);
        expect([for (final kept in await old.notes()) (kept.clientId, kept.queued)],
          [('pinning', true), ('unsent', true), ('sent', true)]);
        expect([await old.waiting(), await old.earlierCount()], [2, 0]);
      });
    });

    test('upgrades a phone from version 12: its notes are not from the watch, and a watch note keeps its mark', () async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
      final file = File('${tempFolder().path}/relay.db');
      final made = Store(NativeDatabase(file));
      await made.get('x');
      await made.close();
      final old = Store(NativeDatabase(file, setup: (db) {
        if (db.userVersion != 13) return;
        db.execute('ALTER TABLE notes DROP COLUMN source');
        db.execute("INSERT INTO notes (client_id, body, created_at, kind, audio_path, duration_ms) VALUES (?, ?, 1, 'voice', ?, 3000)",
          ['old', jsonEncode(note('old').toJson()), 'voice/old.wav']);
        db.execute('PRAGMA user_version = 12');
      }));
      addTearDown(old.close);
      expect([for (final kept in await old.notes()) (kept.clientId, kept.fromWatch)], [('old', false)]);
      await old.addVoiceNote(LocalNote(clientId: 'w', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/w.wav',
        durationMs: 2000, fromWatch: true));
      expect(await old.setWords('w', '', send: false), isTrue);
      final watch = (await old.notes()).firstWhere((kept) => kept.clientId == 'w');
      expect([watch.fromWatch, watch.noWords, watch.queued, await old.earlierCount(), await old.earlierCount(fromWebhook: true)],
        [true, true, false, 1, 1]);
    });

    test('keeps small values by name', () async {
      expect(await store.get('x'), isNull);
      await store.set('x', '1');
      await store.set('x', '2');
      expect(await store.get('x'), '2');
    });
  });
}

