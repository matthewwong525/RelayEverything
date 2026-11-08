import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relay_app/data/api.dart' show Failure;
import 'package:relay_app/data/outbox.dart';
import 'package:relay_app/data/store.dart';

import 'fakes.dart';

final at = DateTime.fromMillisecondsSinceEpoch(1793797200000);
final later = at.add(const Duration(minutes: 5));

LocalNote note(String id, [String text = 'Buy milk']) => LocalNote(clientId: id, text: text, createdAt: at);

void main() {
  late Store store;
  setUp(() => store = memoryStore());
  tearDown(() => store.close());

  Future<LocalNote> kept(String id) async => (await store.notes()).singleWhere((note) => note.clientId == id);

  group('a change to a note', () {
    test('not sent yet changes its waiting upload, and sends as one new note', () async {
      await store.addNote(note('n1'), send: true);
      expect(await store.editNote('n1', 'Buy oat milk', send: true, at: later), isTrue);
      final outbox = await store.outbox();
      expect([for (final item in outbox) (item.route, item.body['text'])], [('notes', 'Buy oat milk')]);
      expect([(await kept('n1')).text, (await kept('n1')).editedAt], ['Buy oat milk', later]);
    });

    test('kept with sending off changes only the note', () async {
      await store.addNote(note('n1'));
      expect(await store.editNote('n1', 'Buy oat milk', send: false, at: later), isTrue);
      expect([(await store.outbox()).length, (await kept('n1')).text], [0, 'Buy oat milk']);
    });

    test('with the same words and no file changes nothing', () async {
      await store.addNote(note('n1'), send: true);
      expect(await store.editNote('n1', 'Buy milk', send: true, at: later), isFalse);
      expect(await store.editNote('gone', 'Buy milk', send: true, at: later), isFalse);
      expect((await kept('n1')).editedAt, isNull);
    });

    test('to a sent note gets one change upload, and a change still waiting takes the newest words', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.editNote('n1', 'Buy oat milk', send: true, at: later);
      await store.editNote('n1', 'Buy oat milk and eggs', send: true, at: later.add(const Duration(minutes: 1)));
      final outbox = await store.outbox();
      expect([for (final item in outbox) (item.route, item.body['text'])], [(noteUpdate, 'Buy oat milk and eggs')]);
      expect(outbox.single.body['editedAt'], later.add(const Duration(minutes: 1)).millisecondsSinceEpoch);
    });

    test('to a sent note adds its new files, and their uploads go after the change', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f1');
      expect(await store.editNote('n1', 'Buy milk', files: const [file], send: true, at: later), isTrue);
      expect([for (final item in await store.outbox()) item.route], [noteUpdate, 'attachment']);
      expect([for (final file in (await store.outbox()).first.body['attachments'] as List) file['name']], ['a.pdf']);
    });

    test('sent while offline sends only the newest words once back online, as PATCH notes', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.editNote('n1', 'One', send: true, at: later);
      final offline = FakeServer((_) => FakeServer.json({}, 503));
      expect((await flush(store, offline.api(connection))).failure, Failure.offline);
      await store.editNote('n1', 'Two', send: true, at: later);
      final server = FakeServer((request) => FakeServer.json({'id': 1, 'updated': true}));
      expect((await flush(store, server.api(connection))).sent, 1);
      final request = server.requests.single;
      expect([request.method, request.url.path], ['PATCH', '/apps/relay/api/notes']);
      expect(jsonDecode(request.body), {'clientId': 'n1', 'text': 'Two'});
      expect(await store.waiting(), 0);
    });

    test('a server that does not know the note drops the change, so it holds back nothing', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.editNote('n1', 'One', send: true, at: later);
      final server = FakeServer((_) => FakeServer.json({}, 404));
      expect((await flush(store, server.api(connection))).dropped, 1);
      expect(await store.waiting(), 0);
    });

    test('made while its first upload is on its way turns that upload into a change', () async {
      await store.addNote(note('n1'), send: true);
      final server = FakeServer()..hold = Completer<void>();
      final round = flush(store, server.api(connection), clock: () => at);
      await pumpEventQueue();
      await store.editNote('n1', 'Buy oat milk', send: true, at: later);
      server.hold!.complete();
      await round;
      expect([for (final item in await store.outbox()) (item.route, item.body['text'])], [(noteUpdate, 'Buy oat milk')]);
      server.hold = null;
      await flush(store, server.api(connection), clock: () => at);
      expect([server.requests.last.method, await store.waiting()], ['PATCH', 0]);
    });
  });

  group('a note left with no words', () {
    test('not sent yet is deleted with its waiting upload, and other notes stay', () async {
      await store.addNote(note('n1'), send: true);
      await store.addNote(note('n2', 'Call Sam'), send: true);
      expect(await store.dropEmptyNote('n1'), isTrue);
      expect([for (final kept in await store.notes()) kept.clientId], ['n2']);
      expect([for (final item in await store.outbox()) item.body['clientId']], ['n2']);
      expect(await store.dropEmptyNote('n1'), isFalse);
    });

    test('already sent is deleted with its waiting change, so the server keeps its last words', () async {
      await store.addNote(note('n1'), send: true);
      final server = FakeServer();
      await flush(store, server.api(connection), clock: () => at);
      await store.editNote('n1', 'Buy oat milk', send: true, at: later);
      expect([for (final item in await store.outbox()) item.route], [noteUpdate]);
      expect(await store.dropEmptyNote('n1'), isTrue);
      expect([await store.notes(), await store.waiting()], [isEmpty, 0]);
      await flush(store, server.api(connection), clock: () => at);
      expect(server.requests, hasLength(1));
    });

    test('with a file, a recording, or words still coming stays', () async {
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f1');
      await store.addNote(LocalNote(clientId: 'file', text: '', createdAt: at, attachments: const [file]), send: true);
      await store.addVoiceNote(LocalNote(clientId: 'voice', text: '', createdAt: at, kind: NoteKind.voice,
        audioPath: 'voice/voice.m4a', durationMs: 2000));
      await store.setWords('voice', 'Hello', send: true);
      await store.addVoiceNote(LocalNote(clientId: 'coming', text: '', createdAt: at, kind: NoteKind.voice,
        audioPath: 'voice/coming.m4a', durationMs: 2000));
      for (final id in ['file', 'voice', 'coming']) {
        expect(await store.dropEmptyNote(id), isFalse, reason: id);
      }
      expect((await store.notes()).length, 3);
      expect([for (final item in await store.outbox()) item.route], ['notes', 'attachment', 'notes']);
    });
  });

  test('upgrades a phone from before changes: every note stays, and can change', () async {
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
        'CREATE TABLE calendar_sent (key TEXT PRIMARY KEY, hash TEXT NOT NULL)',
      ]) {
        db.execute(statement);
      }
      db.execute('INSERT INTO notes (client_id, body, created_at, sent_at, queued) VALUES (?, ?, 1, 2, 1)',
        ['kept', jsonEncode(note('kept').toJson())]);
      db.execute('PRAGMA user_version = 6');
    }));
    addTearDown(old.close);
    expect([for (final kept in await old.notes()) (kept.clientId, kept.editedAt)], [('kept', null)]);
    expect(await old.editNote('kept', 'Changed', send: true, at: later), isTrue);
    expect([for (final item in await old.outbox()) item.route], [noteUpdate]);
    expect((await old.notes()).single.editedAt, later);
  });
}
