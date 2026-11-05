import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/outbox.dart';
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
  });

  group('the API', () {
    test('sends the key in both Access headers, and the body as JSON', () async {
      final server = FakeServer();
      expect(await server.api(connection).post('notes', {'text': 'hi'}), {'added': 1});
      final request = server.requests.single;
      expect(request.url.toString(), 'https://relay.example.com/apps/relay/api/notes');
      expect(request.headers['CF-Access-Client-Id'], 'phone.access');
      expect(request.headers['CF-Access-Client-Secret'], 'secret-value');
      expect(jsonDecode(request.body), {'text': 'hi'});
    });

    test('reads the timeline with each place as a name or coordinates', () async {
      final server = FakeServer((_) => FakeServer.json({'notes': [
        {'id': 'a', 'source': 'ring', 'text': '', 'recordedAt': 1793797260000, 'device': 'Pebble app', 'audio': true,
          'place': {'lat': 43.66291, 'lon': -79.39572, 'accuracy': null, 'name': null, 'from': 'history'}},
        {'id': 'b', 'source': 'typed', 'text': 'Hi', 'recordedAt': 1793797200000, 'device': 'Phone', 'audio': false,
          'place': {'lat': 43.6, 'lon': -79.3, 'accuracy': 5, 'name': 'King St W', 'from': 'phone'}},
        {'id': 'c', 'source': 'typed', 'text': 'No place', 'recordedAt': 1793797100000, 'device': 'Phone', 'audio': false, 'place': null},
      ], 'next': 1793797100000, 'nextId': 'c'}));
      final page = await server.api(connection).timeline(before: (at: 1793797300000, id: 'd'));
      expect(server.requests.single.url.queryParameters, {'before': '1793797300000', 'beforeId': 'd'});
      expect([for (final note in page.notes) note.place], ['43.6629, -79.3957', 'King St W', null]);
      expect(page.notes.first.audio, isTrue);
      expect(page.notes.first.json['id'], 'a');
      expect(page.next, (at: 1793797100000, id: 'c'));
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
      await expectLater(api.timeline(), throwsA(isA<ApiException>().having((error) => error.failure, 'failure', Failure.offline)));
      expect(const ApiException(Failure.offline, 503).toString(), contains('503'));
    });
  });

  group('the store and outbox', () {
    late Store store;
    setUp(() => store = memoryStore());
    tearDown(() => store.close());

    final pin = Pin(at: at, lat: 43.65, lon: -79.38, accuracy: 12, place: 'King St W');
    LocalNote note(String id, {Pin? pin}) => LocalNote(clientId: id, text: 'Note $id', createdAt: DateTime.fromMillisecondsSinceEpoch(1793797200000), pin: pin);

    test('keeps a note with no upload while sending is off, and queues the earlier ones oldest first on request', () async {
      LocalNote at_(String id, int minute) =>
        LocalNote(clientId: id, text: 'Note $id', createdAt: at.add(Duration(minutes: minute)));
      await store.addNote(at_('late', 2));
      await store.addNote(at_('early', 0));
      await store.addNote(at_('pinning', 1), waitForPin: true);
      expect([await store.earlierCount(), (await store.outbox()).length, await store.waiting()], [2, 0, 1]);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.queued, kept.pinning, kept.sentAt)],
        [('late', false, false, null), ('pinning', false, true, null), ('early', false, false, null)]);
      // A note settled with sending off stays only here, and counts as earlier.
      expect(await store.settlePin('pinning', pin, send: false), isTrue);
      expect([await store.earlierCount(), (await store.outbox()).length], [3, 0]);
      await store.queueEarlier();
      expect([for (final item in await store.outbox()) item.body['clientId']], ['early', 'pinning', 'late']);
      expect((await store.outbox())[1].body['place'], 'King St W');
      expect(await store.earlierCount(), 0);
      await flush(store, FakeServer().api(connection), clock: () => at);
      expect([for (final kept in await store.notes()) kept.sentAt], [at, at, at]);
    });

    test('drops waiting health and location, and keeps note uploads', () async {
      await store.addNote(note('note-0001'), send: true);
      await store.enqueue('health', {'samples': []});
      await store.addPoint(Pin(at: at, lat: 1, lon: 1, accuracy: 1));
      await store.queuePoints();
      await store.addPoint(Pin(at: at.add(const Duration(minutes: 1)), lat: 1, lon: 1, accuracy: 1));
      await store.dropReadings();
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      await store.queuePoints();
      expect(await store.waiting(), 1);
    });

    test('keeps each upload under its destination', () async {
      await store.enqueue('notes', {'clientId': 'a'});
      await store.enqueue('notes', {'clientId': 'b'}, destination: 'webhook');
      expect([for (final item in await store.outbox()) item.body['clientId']], ['a']);
      expect([for (final item in await store.outbox(destination: 'webhook')) item.body['clientId']], ['b']);
    });

    test('keeps a typed note as waiting until its upload lands, in order', () async {
      await store.addNote(note('note-0001', pin: pin), send: true);
      await store.addNote(note('note-0002'), send: true);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.queued)], unorderedEquals([('note-0001', true), ('note-0002', true)]));
      expect((await store.notes()).firstWhere((kept) => kept.clientId == 'note-0001').pin!.place, 'King St W');
      final server = FakeServer();
      final result = await flush(store, server.api(connection));
      expect([result.sent, result.dropped, result.failure], [2, 0, null]);
      expect([for (final request in server.requests) jsonDecode(request.body)['clientId']], ['note-0001', 'note-0002']);
      expect(jsonDecode(server.requests.first.body), containsPair('place', 'King St W'));
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

    test('upgrades a first-version phone: sent notes keep a send time, and a note waiting for its pin still waits', () async {
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
      expect([for (final kept in await old.notes()) (kept.clientId, kept.sentAt?.millisecondsSinceEpoch, kept.queued, kept.pinning)],
        [('pinning', null, false, true), ('queued', null, true, false), ('sent', 1, true, false)]);
      expect([for (final item in await old.outbox()) item.body['clientId']], ['queued']);
      await old.settleWaiting(send: true);
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

    test('a voice note given words with sending off stays only here, and counts as earlier', () async {
      await store.addVoiceNote(LocalNote(clientId: 'v', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/v.wav'));
      expect(await store.setWords('v', 'Words', send: false), isTrue);
      expect([await store.earlierCount(), (await store.outbox()).length], [1, 0]);
      await store.addVoiceNote(LocalNote(clientId: 'silent', text: '', createdAt: at, kind: NoteKind.voice, audioPath: 'voice/silent.wav'));
      await store.dropNote('silent');
      expect([for (final note in await store.notes()) note.clientId], ['v']);
    });

    test('keeps small values by name', () async {
      expect(await store.get('x'), isNull);
      await store.set('x', '1');
      await store.set('x', '2');
      expect(await store.get('x'), '2');
    });
  });
}

