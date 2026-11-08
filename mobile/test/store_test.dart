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
      expect(jsonDecode(request.body), {'clientId': 'n1', 'text': 'Two', 'editedAt': later.millisecondsSinceEpoch});
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

  group('a pulled note', () {
    test('of this phone, pulled back, stays one note with its server id', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      expect(await store.applyPulled([pulledNote('s1', clientId: 'n1', mine: true, text: 'Buy milk', recordedAt: at)]), isTrue);
      await store.applyPulled([pulledNote('s1', clientId: 'n1', mine: true, text: 'Buy oat milk', recordedAt: at)]);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.serverId, kept.mine, kept.text)],
        [('n1', 's1', true, 'Buy oat milk')]);
      expect(await store.outbox(), isEmpty);
    });

    test('of this phone under a new key, called not its own, stays one note, and its change goes by its server id', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.applyPulled([pulledNote('s1', clientId: 'n1', text: 'Buy milk', recordedAt: at, device: 'Android phone')]);
      expect([for (final kept in await store.notes()) (kept.clientId, kept.serverId, kept.mine)], [('n1', 's1', true)]);
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f1');
      expect(await store.editNote('n1', 'Buy oat milk', files: const [file], send: true, at: later), isTrue);
      // The new device may add no file to the old device's note: the words go once more without the list.
      final server = FakeServer((request) => switch (request.method) {
        'PATCH' when (jsonDecode(request.body) as Map).containsKey('attachments') =>
          FakeServer.json({'error': {'code': 'not_own', 'message': 'Add a file only to a note this phone sent.'}}, 400),
        'PATCH' => FakeServer.json({'id': 's1', 'updated': true}),
        _ => FakeServer.json({}, 404),
      });
      await flush(store, server.api(connection));
      final edit = {'id': 's1', 'text': 'Buy oat milk', 'editedAt': later.millisecondsSinceEpoch};
      expect([for (final request in server.requests) if (request.method == 'PATCH') jsonDecode(request.body)], [
        {...edit, 'attachments': [{'id': 'f1', 'name': 'a.pdf', 'type': 'application/pdf', 'size': 1}]},
        edit,
      ]);
      expect(await store.waiting(), 0);
    });

    test('of this phone, with a change queued before the pull, sends that change by its server id', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.editNote('n1', 'Buy oat milk', send: true, at: later);
      await store.applyPulled([pulledNote('s1', clientId: 'n1', text: 'Buy milk', recordedAt: at)]);
      expect([for (final item in await store.outbox()) (item.route, item.body['id'], item.body['text'])],
        [(noteUpdate, 's1', 'Buy oat milk')]);
    });

    test('older than this phone\'s last edit, with nothing waiting, keeps the phone\'s words and queues their change', () async {
      await store.applyPulled([pulledNote('s11', text: 'Old words', recordedAt: at)]);
      // Changed with sending off: the edit time moves, and nothing waits.
      await store.editNote('srv:s11', 'Phone words', send: false, at: later);
      expect(await store.outbox(), isEmpty);
      await store.applyPulled([pulledNote('s11', text: 'Server words', recordedAt: at,
        editedAt: later.subtract(const Duration(minutes: 1)))]);
      expect([(await kept('srv:s11')).text, (await kept('srv:s11')).editedAt], ['Phone words', later]);
      expect([for (final item in await store.outbox()) (item.route, item.body['id'], item.body['text'], item.body['editedAt'])],
        [(noteUpdate, 's11', 'Phone words', later.millisecondsSinceEpoch)]);
    });

    test('with the same words as this phone\'s later edit queues nothing, as when the phone clock runs ahead', () async {
      await store.applyPulled([pulledNote('s12', text: 'Old words', recordedAt: at)]);
      await store.editNote('srv:s12', 'Same words', send: false, at: later);
      await store.applyPulled([pulledNote('s12', text: 'Same words', recordedAt: at,
        editedAt: later.subtract(const Duration(seconds: 30)))]);
      expect([(await kept('srv:s12')).text, await store.outbox()], ['Same words', isEmpty]);
    });

    test('older than this phone\'s sent edit, from a phone clock that runs ahead, queues nothing and its words win', () async {
      await store.applyPulled([pulledNote('s14', text: 'Old words', recordedAt: at)]);
      // The phone's clock is an hour fast: the server took the edit, and keeps it at its own, earlier time.
      final fast = at.add(const Duration(hours: 1));
      await store.editNote('srv:s14', 'Phone words', send: true, at: fast);
      await flush(store, FakeServer().api(connection), clock: () => at);
      expect(await store.outbox(), isEmpty);
      // Another phone changed the note after that, at a time still earlier than this phone's clock.
      await store.applyPulled([pulledNote('s14', text: 'Newer words', recordedAt: at,
        editedAt: at.add(const Duration(minutes: 30)))]);
      expect([(await kept('srv:s14')).text, await store.outbox()], ['Newer words', isEmpty]);
    });

    test('older than this phone\'s dropped edit queues nothing and its words win', () async {
      await store.applyPulled([pulledNote('s15', text: 'Old words', recordedAt: at)]);
      await store.editNote('srv:s15', 'Phone words', send: true, at: later);
      expect((await flush(store, FakeServer((_) => FakeServer.json({}, 404)).api(connection))).dropped, 1);
      await store.applyPulled([pulledNote('s15', text: 'Server words', recordedAt: at)]);
      expect([(await kept('srv:s15')).text, await store.outbox()], ['Server words', isEmpty]);
    });

    test('newer than this phone\'s last edit takes the pulled words', () async {
      await store.applyPulled([pulledNote('s13', text: 'Old words', recordedAt: at)]);
      await store.editNote('srv:s13', 'Phone words', send: false, at: later);
      await store.applyPulled([pulledNote('s13', text: 'Newer words', recordedAt: at, editedAt: later.add(const Duration(minutes: 1)))]);
      expect([(await kept('srv:s13')).text, await store.outbox()], ['Newer words', isEmpty]);
    });

    test('from elsewhere is added once, as srv: and its id, with its files not on the phone, and never sent as new', () async {
      final email = pulledNote('s2', files: [{'id': 'f1', 'name': 'ticket.pdf', 'type': 'application/pdf', 'size': 3, 'ready': true}]);
      await store.applyPulled([email]);
      await store.applyPulled([email]);
      final kept = (await store.notes()).single;
      expect([kept.clientId, kept.serverId, kept.mine, kept.device, kept.text],
        ['srv:s2', 's2', false, 'Email', 'Flight moved to 9:40']);
      expect([for (final file in kept.attachments) (file.id, file.path)], [('f1', '')]);
      await store.queueEarlier();
      expect([await store.earlierCount(), await store.outbox()], [0, isEmpty]);
    });

    test('with a waiting change made later keeps this phone\'s words', () async {
      await store.applyPulled([pulledNote('s3', text: 'Old words', recordedAt: at)]);
      await store.editNote('srv:s3', 'Phone words', send: true, at: later);
      await store.applyPulled([pulledNote('s3', text: 'Server words', recordedAt: at,
        editedAt: later.subtract(const Duration(minutes: 1)))]);
      expect((await kept('srv:s3')).text, 'Phone words');
      expect([for (final item in await store.outbox()) (item.route, item.body['id'], item.body['text'])],
        [(noteUpdate, 's3', 'Phone words')]);
    });

    test('newer than a waiting change drops that change, and its words win', () async {
      await store.applyPulled([pulledNote('s4', text: 'Old words', recordedAt: at)]);
      await store.editNote('srv:s4', 'Phone words', send: true, at: later);
      await store.applyPulled([pulledNote('s4', text: 'Newer words', recordedAt: at, editedAt: later.add(const Duration(minutes: 1)))]);
      expect([(await kept('srv:s4')).text, await store.outbox()], ['Newer words', isEmpty]);
    });

    test('open in the editor is left as it is, and the rest of the page is kept', () async {
      await store.applyPulled([pulledNote('s5', text: 'One')]);
      expect(await store.applyPulled([pulledNote('s5', text: 'Two'), pulledNote('s6')], editing: 'srv:s5'), isFalse);
      expect([(await kept('srv:s5')).text, await store.hasNote('srv:s6')], ['One', isTrue]);
    });

    test('from a ring with a recording is a voice note, with its recording as a file to download', () async {
      await store.applyPulled([pulledNote('s7', source: 'ring', audio: true, device: 'Ring')]);
      final kept = (await store.notes()).single;
      expect([kept.kind, kept.audioPath, [for (final file in kept.attachments) (file.id, file.type)]],
        [NoteKind.voice, null, [('${recordingPrefix}s7', 'audio/mp4')]]);
    });
  });

  group('a change to a note from elsewhere', () {
    test('goes as PATCH notes by its server id with its edit time, and its new files stay on the phone', () async {
      await store.applyPulled([pulledNote('s8')]);
      const file = Attachment(id: 'f9', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f9');
      expect(await store.editNote('srv:s8', 'Flight moved to 9:40, seen', files: const [file], send: true, at: later), isTrue);
      expect([for (final item in await store.outbox()) item.route], [noteUpdate]);
      final server = FakeServer((_) => FakeServer.json({'id': 's8', 'updated': true}));
      expect((await flush(store, server.api(connection))).sent, 1);
      final request = server.requests.single;
      expect([request.method, request.url.path], ['PATCH', '/apps/relay/api/notes']);
      expect(jsonDecode(request.body), {'id': 's8', 'text': 'Flight moved to 9:40, seen', 'editedAt': later.millisecondsSinceEpoch});
    });

    test('refused as older (409) leaves the outbox, and the next pull takes the stored note', () async {
      await store.applyPulled([pulledNote('s9', text: 'Old', recordedAt: at)]);
      await store.editNote('srv:s9', 'Phone words', send: true, at: later);
      final server = FakeServer((_) => FakeServer.json({'error': {'code': 'older', 'message': 'A newer change is kept.'}}, 409));
      final result = await flush(store, server.api(connection));
      expect([result.sent, result.dropped, result.failure], [0, 1, null]);
      expect(await store.waiting(), 0);
      // Nothing waits now, so the pull right after the outbox takes the newer words.
      await store.applyPulled([pulledNote('s9', text: 'Newer from the laptop', recordedAt: at, editedAt: later.add(const Duration(minutes: 1)))]);
      expect((await kept('srv:s9')).text, 'Newer from the laptop');
    });
  });

  test('sign-out deletes the notes from elsewhere, their files and changes, and the pull\'s place', () async {
    await store.addNote(note('mine'));
    await store.applyPulled([pulledNote('s10', files: [{'id': 'f1', 'name': 'ticket.pdf', 'type': 'application/pdf', 'size': 3}])]);
    final copy = await store.photoFile('attachments/f1.pdf');
    await copy.parent.create(recursive: true);
    await copy.writeAsString('pdf');
    await store.fileKept('f1', 'attachments/f1.pdf');
    await store.editNote('srv:s10', 'Seen', send: true, at: later);
    await store.set(noteSyncSeq, '42');
    await store.dropSynced();
    expect([for (final kept in await store.notes()) kept.clientId], ['mine']);
    expect([await copy.exists(), await store.get(noteSyncSeq), await store.outbox(), await store.attachmentsOf('srv:s10')],
      [false, null, isEmpty, isEmpty]);
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

  test('upgrades a phone from version 8: its notes stay its own, and a pull adds each note once', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
    final old = Store(NativeDatabase.memory(setup: (db) {
      for (final statement in [
        "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
          'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
          "queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'typed', "
          'audio_path TEXT, duration_ms INTEGER, words_pending INTEGER NOT NULL DEFAULT 0, edited_at INTEGER)',
        'CREATE TABLE points (at INTEGER PRIMARY KEY, body TEXT NOT NULL)',
        'CREATE TABLE state (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        'CREATE TABLE attachments (id TEXT PRIMARY KEY, note_client_id TEXT NOT NULL, name TEXT, type TEXT, size INTEGER, '
          'path TEXT, sent_at INTEGER)',
        'CREATE TABLE calendar_sent (key TEXT PRIMARY KEY, hash TEXT NOT NULL)',
        'CREATE TABLE photos (client_id TEXT PRIMARY KEY, asset_id TEXT NOT NULL, taken_at INTEGER NOT NULL, lat REAL, lon REAL, '
          'width INTEGER NOT NULL, height INTEGER NOT NULL, path TEXT NOT NULL, created_at INTEGER NOT NULL)',
      ]) {
        db.execute(statement);
      }
      db.execute('INSERT INTO notes (client_id, body, created_at, sent_at, queued) VALUES (?, ?, 1, 2, 1)',
        ['kept', jsonEncode(note('kept').toJson())]);
      db.execute('PRAGMA user_version = 8');
    }));
    addTearDown(old.close);
    expect([for (final kept in await old.notes()) (kept.clientId, kept.mine, kept.serverId)], [('kept', true, null)]);
    await old.applyPulled([pulledNote('s1', clientId: 'kept', mine: true, text: 'Buy milk'), pulledNote('s2'), pulledNote('s2')]);
    expect([for (final kept in await old.notes()) (kept.clientId, kept.serverId)]..sort((a, b) => a.$1.compareTo(b.$1)),
      [('kept', 's1'), ('srv:s2', 's2')]);
  });
}
