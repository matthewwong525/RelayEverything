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
    test('never sent and never queued is deleted, and other notes stay', () async {
      await store.addNote(note('n1'));
      await store.addNote(note('n2', 'Call Sam'), send: true);
      expect(await store.dropEmptyNote('n1'), isTrue);
      expect([for (final kept in await store.notes()) kept.clientId], ['n2']);
      expect([for (final item in await store.outbox()) item.body['clientId']], ['n2']);
      expect(await store.dropEmptyNote('n1'), isFalse);
    });

    test('with its first upload waiting or on its way stays for a delete everywhere, as the upload may land', () async {
      await store.addNote(note('n1'), send: true);
      expect([await store.isBare('n1'), await store.dropEmptyNote('n1')], [isTrue, isFalse]);
      expect([for (final kept in await store.notes()) kept.clientId], ['n1']);
      expect(await store.deleteNote('n1'), isTrue);
      final outbox = await store.outbox();
      expect([[for (final item in outbox) item.route], outbox.single.body], [[noteDelete], {'clientId': 'n1'}]);
    });

    test('already sent stays for a delete everywhere, as the server has it', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.editNote('n1', 'Buy oat milk', send: true, at: later);
      expect([await store.isBare('n1'), await store.dropEmptyNote('n1')], [isTrue, isFalse]);
      expect([for (final kept in await store.notes()) kept.clientId], ['n1']);
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

  group('a deleted note', () {
    test('marked is hidden from the list, the count and earlier notes, and Undo brings it back as it was', () async {
      await store.addNote(note('n1'));
      await store.addNote(note('n2', 'Call Sam'));
      await store.markDeleted('n1', at);
      expect([[for (final kept in await store.notes()) kept.clientId], await store.earlierCount()], [['n2'], 1]);
      expect(await store.marked(), [('n1', at)]);
      await store.undoDelete('n1');
      expect([[for (final kept in await store.notes()) kept.clientId]..sort(), await store.earlierCount(), await store.marked()],
        [['n1', 'n2'], 2, isEmpty]);
    });

    test('never sent goes from the phone with its files and queues nothing', () async {
      final copy = await store.photoFile('attachments/f1.pdf');
      await copy.parent.create(recursive: true);
      await copy.writeAsString('pdf');
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 3, path: 'attachments/f1.pdf');
      await store.addNote(LocalNote(clientId: 'n1', text: 'Ticket', createdAt: at, attachments: const [file]));
      expect(await store.deleteNote('n1'), isFalse);
      expect([await store.notes(), await store.outbox(), await store.attachmentsOf('n1'), await copy.exists()],
        [isEmpty, isEmpty, isEmpty, false]);
      expect(await store.deleteNote('gone'), isFalse);
    });

    test('sent queues one note.delete by its server id, and its waiting change and files go', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.applyPulled([pulledNote('s1', clientId: 'n1', mine: true, text: 'Buy milk', recordedAt: at)]);
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 1, path: 'attachments/f1');
      await store.editNote('n1', 'Buy oat milk', files: const [file], send: true, at: later);
      expect([for (final item in await store.outbox()) item.route], [noteUpdate, 'attachment']);
      expect(await store.deleteNote('n1'), isTrue);
      final outbox = await store.outbox();
      expect([[for (final item in outbox) item.route], outbox.single.body], [[noteDelete], {'clientId': 'n1', 'id': 's1'}]);
      expect([await store.notes(), await store.attachmentsOf('n1'), await store.waiting()], [isEmpty, isEmpty, 1]);
    });

    test('with its upload still waiting queues a note.delete by its clientId, as the upload may be on its way', () async {
      await store.addNote(note('n1'), send: true);
      expect(await store.deleteNote('n1'), isTrue);
      final outbox = await store.outbox();
      expect([[for (final item in outbox) item.route], outbox.single.body], [[noteDelete], {'clientId': 'n1'}]);
    });

    test('from elsewhere, pulled as deleted, goes with its files, and an unknown id changes nothing', () async {
      await store.applyPulled([pulledNote('s1', files: [{'id': 'f1', 'name': 'ticket.pdf', 'type': 'application/pdf', 'size': 3}])]);
      final copy = await store.photoFile('attachments/f1.pdf');
      await copy.parent.create(recursive: true);
      await copy.writeAsString('pdf');
      await store.fileKept('f1', 'attachments/f1.pdf');
      await store.editNote('srv:s1', 'Seen', send: true, at: later);
      expect(await store.applyPulled([{'id': 's1', 'clientId': 'email:m-1', 'deleted': true}, {'id': 's9', 'clientId': null, 'deleted': true}]),
        isTrue);
      expect([await store.notes(), await store.outbox(), await store.attachmentsOf('srv:s1'), await copy.exists()],
        [isEmpty, isEmpty, isEmpty, false]);
    });

    test('of this phone, pulled as deleted before a pull gave its server id, is found by its clientId', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.applyPulled([{'id': 's1', 'clientId': 'n1', 'deleted': true}]);
      expect([await store.notes(), await store.outbox()], [isEmpty, isEmpty]);
    });

    test('pulled as deleted while open in the editor, or marked deleted here, stays for now', () async {
      await store.applyPulled([pulledNote('s1'), pulledNote('s2')]);
      await store.markDeleted('srv:s2', at);
      expect(await store.applyPulled([{'id': 's1', 'clientId': null, 'deleted': true}, {'id': 's2', 'clientId': null, 'deleted': true}],
        editing: 'srv:s1'), isFalse);
      expect([for (final kept in await store.notes()) kept.clientId], ['srv:s1']);
      expect(await store.marked(), [('srv:s2', at)]);
    });

    test('pulled as deleted while marked here holds the sync place, so after Undo the next pull deletes it', () async {
      await store.applyPulled([pulledNote('s1'), pulledNote('s2')]);
      await store.markDeleted('srv:s1', at);
      final gone = {'id': 's1', 'clientId': null, 'deleted': true};
      expect(await store.applyPulled([gone]), isFalse);
      expect(await store.marked(), [('srv:s1', at)]);
      await store.undoDelete('srv:s1');
      expect(await store.applyPulled([gone]), isTrue);
      expect([[for (final kept in await store.notes()) kept.clientId], await store.marked()], [['srv:s2'], isEmpty]);
    });
  });

  group('a pin', () {
    List<(String, Object?, Object?, Object?)> pins(List<OutboxItem> items) =>
      [for (final item in items) (item.route, item.body['id'], item.body['pinned'], item.body['at'])];

    test('keeps the note\'s words and time, shows in the list, and a second pin the same way changes nothing', () async {
      await store.addNote(note('n1'));
      expect(await store.pinNote('n1', true, send: false, at: later), isTrue);
      expect(await store.pinNote('n1', true, send: false, at: later), isFalse);
      expect(await store.pinNote('gone', true, send: false, at: later), isFalse);
      final pinned = await kept('n1');
      expect([pinned.pinned, pinned.text, pinned.createdAt, pinned.editedAt], [true, 'Buy milk', at, null]);
      expect(await store.outbox(), isEmpty);
      expect(await store.pinNote('n1', false, send: false, at: later), isTrue);
      expect((await kept('n1')).pinned, isFalse);
    });

    test('of a sent note queues one note.pin, and a later pin replaces the one still waiting', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.pinNote('n1', true, send: true, at: at);
      await store.pinNote('n1', false, send: true, at: later);
      expect(pins(await store.outbox()), [(notePin, null, false, later.millisecondsSinceEpoch)]);
    });

    test('of a note not sent yet goes after the note\'s own upload, and a note never queued queues no pin', () async {
      await store.addNote(note('n1'), send: true);
      await store.pinNote('n1', true, send: true, at: later);
      expect([for (final item in await store.outbox()) item.route], ['notes', notePin]);
      await store.addNote(note('n2'));
      await store.pinNote('n2', true, send: true, at: later);
      expect((await store.outbox()).length, 2);
    });

    test('of a note kept while sending was off goes after its upload once it is queued', () async {
      await store.addNote(note('n1'));
      await store.pinNote('n1', true, send: false, at: later);
      await store.queueEarlier();
      expect(pins(await store.outbox()), [('notes', null, null, null), (notePin, null, true, later.millisecondsSinceEpoch)]);
    });

    test('goes as PUT notes/pin by clientId, or by the server id once a pull saved it, and a webhook gets no pin', () async {
      await store.addNote(note('n1'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.pinNote('n1', true, send: true, at: later);
      final server = FakeServer((_) => FakeServer.json({'id': 's1', 'pinned': true, 'updated': true}));
      await flush(store, server.api(connection));
      expect([server.requests.single.method, server.requests.single.url.path], ['PUT', '/apps/relay/api/notes/pin']);
      expect(jsonDecode(server.requests.single.body), {'clientId': 'n1', 'pinned': true, 'at': later.millisecondsSinceEpoch});
      await store.pinNote('n1', false, send: true, at: later.add(const Duration(minutes: 1)));
      await store.applyPulled([pulledNote('s1', clientId: 'n1', mine: true, text: 'Buy milk', recordedAt: at, pinned: true,
        pinChangedAt: later)]);
      expect(pins(await store.outbox()), [(notePin, 's1', false, later.add(const Duration(minutes: 1)).millisecondsSinceEpoch)]);
      expect((await kept('n1')).pinned, isFalse, reason: 'the pin still waiting is newer than the pulled one');
      await store.moveOutbox(ownWebhook);
      final receiver = FakeServer();
      expect((await flush(store, receiver.webhook(hook, installId))).sent, 1);
      expect(receiver.requests, isEmpty);
    });

    test('refused as older (409) leaves the outbox, and the next pull takes the newer pin', () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false)]);
      await store.pinNote('srv:s1', false, send: true, at: at);
      await store.pinNote('srv:s1', true, send: true, at: at);
      await store.pinNote('srv:s1', false, send: true, at: later);
      final server = FakeServer((_) => FakeServer.json({'error': {'code': 'older', 'message': 'A newer pin is kept.'}}, 409));
      await flush(store, server.api(connection));
      expect(jsonDecode(server.requests.single.body), {'id': 's1', 'pinned': false, 'at': later.millisecondsSinceEpoch});
      expect(await store.waiting(), 0);
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: true,
        pinChangedAt: later.add(const Duration(minutes: 30)))]);
      expect([(await kept('srv:s1')).pinned, await store.outbox()], [true, isEmpty]);
    });

    test('with the person\'s own webhook, or with sending off, stays on the phone', () async {
      await store.addNote(note('n1'), send: true);
      await store.moveOutbox(ownWebhook);
      await store.pinNote('n1', true, send: true, at: later);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
      await store.applyPulled([pulledNote('s2', text: 'Door code', recordedAt: at)]);
      await store.pinNote('srv:s2', true, send: false, at: later);
      expect([for (final item in await store.outbox()) item.route], ['notes']);
    });

    test('pulled when newer than the phone\'s and none waits is kept; a server from before pins changes nothing', () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: true, pinChangedAt: at)]);
      expect((await kept('srv:s1')).pinned, isTrue);
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at)]);
      expect((await kept('srv:s1')).pinned, isTrue);
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false, pinChangedAt: later)]);
      expect([(await kept('srv:s1')).pinned, await store.outbox()], [false, isEmpty]);
    });

    test('made while sending was off goes once sending turns on, with no pull, and one the server took never goes again',
        () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false)]);
      await store.addNote(note('n1'));
      await store.pinNote('srv:s1', true, send: false, at: later);
      await store.pinNote('n1', true, send: false, at: later);
      expect(await store.outbox(), isEmpty);
      await store.queueUnsentPins();
      expect(pins(await store.outbox()), [(notePin, 's1', true, later.millisecondsSinceEpoch)],
        reason: 'n1 never went, so its pin waits for its own upload');
      await store.queueUnsentPins();
      expect((await store.outbox()).length, 1);
      await flush(store, FakeServer().api(connection));
      await store.queueUnsentPins();
      expect(await store.outbox(), isEmpty);
    });

    test('keeps the server\'s time once it took the pin, so a later pin elsewhere wins over a phone clock set ahead',
        () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false)]);
      final ahead = later.add(const Duration(hours: 1));
      await store.pinNote('srv:s1', true, send: true, at: ahead);
      final server = FakeServer((_) => FakeServer.json({'id': 's1', 'pinned': true, 'pinChangedAt': later.millisecondsSinceEpoch,
        'updated': true}));
      await flush(store, server.api(connection));
      expect((jsonDecode(server.requests.single.body) as Map)['at'], ahead.millisecondsSinceEpoch);
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false,
        pinChangedAt: later.add(const Duration(minutes: 10)))]);
      expect([(await kept('srv:s1')).pinned, await store.outbox()], [false, isEmpty]);
    });

    test('a pull of a note whose pin the server has takes the server\'s pin and time, even an older one', () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false)]);
      await store.pinNote('srv:s1', true, send: true, at: later.add(const Duration(hours: 1)));
      await flush(store, FakeServer().api(connection));
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: true, pinChangedAt: later)]);
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false,
        pinChangedAt: later.add(const Duration(minutes: 1)))]);
      expect([(await kept('srv:s1')).pinned, await store.outbox()], [false, isEmpty]);
    });

    test('made on a phone whose clock runs behind still counts as after the last pin it knows, and a 409 leaves no mark',
        () async {
      final serverAt = later.add(const Duration(minutes: 2));
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: true, pinChangedAt: serverAt)]);
      await store.pinNote('srv:s1', false, send: true, at: later);
      expect(pins(await store.outbox()), [(notePin, 's1', false, serverAt.millisecondsSinceEpoch + 1)]);
      final server = FakeServer((_) => FakeServer.json({'error': {'code': 'older', 'message': 'A newer pin is kept.'}}, 409));
      expect((await flush(store, server.api(connection))).dropped, 1);
      await store.queueUnsentPins();
      expect(await store.outbox(), isEmpty, reason: 'a pin refused as older never goes again');
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: true, pinChangedAt: serverAt)]);
      expect([(await kept('srv:s1')).pinned, await store.outbox()], [true, isEmpty],
        reason: 'the next pull of the note takes the server\'s pin, though it is not newer than the refused one');
    });

    test('refused by a server older than pins is dropped, and the rest still sends; a refused key stops all', () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at, pinned: false)]);
      await store.pinNote('srv:s1', true, send: true, at: later);
      await store.addNote(note('n1'), send: true);
      var keyWorks = true;
      final server = FakeServer((request) => request.method == 'PUT' || (!keyWorks && request.url.path.endsWith('/key'))
        ? FakeServer.json({'error': {'code': 'forbidden', 'message': 'A device key can only send to Relay Everything.'}}, 403)
        : FakeServer.ok(request));
      keyWorks = false;
      final refused = await flush(store, server.api(connection));
      expect([refused.failure, [for (final item in await store.outbox()) item.route]], [Failure.refused, [notePin, 'notes']]);
      keyWorks = true;
      final result = await flush(store, server.api(connection), clock: () => at);
      expect([result.failure, result.sent, result.dropped, await store.outbox()], [null, 1, 1, isEmpty]);
      expect([(await kept('srv:s1')).pinned, (await kept('n1')).sentAt], [true, at]);
    });

    test('of a deleted note, or a sign-out, goes with it', () async {
      await store.applyPulled([pulledNote('s1', text: 'Door code', recordedAt: at)]);
      await store.pinNote('srv:s1', true, send: true, at: later);
      await store.dropSynced();
      expect(await store.outbox(), isEmpty);
      await store.addNote(note('n1'));
      await store.addNote(note('n2'), send: true);
      await flush(store, FakeServer().api(connection), clock: () => at);
      await store.pinNote('n2', true, send: true, at: later);
      await store.deleteNote('n2');
      expect([for (final item in await store.outbox()) item.route], [noteDelete]);
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

  test('upgrades a phone from version 9: it can delete and pin a note, and its next pull starts again from 0', () async {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    addTearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
    final old = Store(NativeDatabase.memory(setup: (db) {
      for (final statement in [
        "CREATE TABLE outbox (id INTEGER PRIMARY KEY AUTOINCREMENT, destination TEXT NOT NULL DEFAULT 'relay-server', "
          'route TEXT NOT NULL, body TEXT NOT NULL, created_at INTEGER NOT NULL)',
        'CREATE TABLE notes (client_id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER NOT NULL, sent_at INTEGER, '
          "queued INTEGER NOT NULL DEFAULT 0, pinning INTEGER NOT NULL DEFAULT 0, kind TEXT NOT NULL DEFAULT 'typed', "
          'audio_path TEXT, duration_ms INTEGER, words_pending INTEGER NOT NULL DEFAULT 0, edited_at INTEGER, '
          'server_id TEXT, device TEXT, mine INTEGER NOT NULL DEFAULT 1, edit_unsent INTEGER NOT NULL DEFAULT 0)',
        'CREATE UNIQUE INDEX notes_server_id ON notes (server_id)',
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
      db.execute('INSERT INTO notes (client_id, body, created_at, sent_at, queued, server_id) VALUES (?, ?, 1, 2, 1, ?)',
        ['kept', jsonEncode(note('kept').toJson()), 's1']);
      db.execute("INSERT INTO state (key, value) VALUES ('$noteSyncSeq', '42')");
      db.execute('PRAGMA user_version = 9');
    }));
    addTearDown(old.close);
    expect([for (final kept in await old.notes()) kept.clientId], ['kept']);
    expect(await old.get(noteSyncSeq), isNull);
    // Version 14 added the pin.
    expect([await old.pinNote('kept', true, send: false, at: at), (await old.notes()).single.pinned], [true, true]);
    await old.markDeleted('kept', at);
    expect(await old.notes(), isEmpty);
    expect(await old.deleteNote('kept'), isTrue);
  });

  group('earlier notes from your own webhook', () {
    /// Keeps note [id], made at [made], and sends it and its files, as a webhook takes them: sent, with no server id.
    Future<void> sentToWebhook(String id, DateTime made, {List<Attachment> files = const []}) async {
      await store.addNote(LocalNote(clientId: id, text: 'Note $id', createdAt: made, attachments: files), send: true);
      for (final item in await store.outbox()) {
        await store.done(item.id);
      }
      await store.noteSent(id, made);
      for (final file in files) {
        await store.attachmentSent(file.id, made);
      }
    }

    test('count and queue only with fromWebhook, oldest first, with their files and newest words', () async {
      const file = Attachment(id: 'f1', name: 'a.pdf', type: 'application/pdf', size: 3, path: 'attachments/f1.pdf');
      await sentToWebhook('w2', at.add(const Duration(minutes: 1)), files: const [file]);
      await sentToWebhook('w1', at);
      // A change that went nowhere yet: the new upload carries it, so it goes.
      expect(await store.editNote('w1', 'Note w1, changed', send: true, at: later), isTrue);
      await store.addNote(LocalNote(clientId: 'p1', text: 'Only here', createdAt: later));
      expect([await store.earlierCount(), await store.earlierCount(fromWebhook: true)], [1, 3]);
      await store.queueEarlier(fromWebhook: true);
      expect([for (final item in await store.outbox()) (item.route, item.body['clientId'] ?? item.body['id'])],
        [('notes', 'w1'), ('notes', 'w2'), ('attachment', 'f1'), ('notes', 'p1')]);
      expect((await store.outbox()).first.body['text'], 'Note w1, changed');
      // Waiting to go, they are not asked about again.
      expect([await store.earlierCount(), await store.earlierCount(fromWebhook: true)], [0, 0]);
    });

    test('without fromWebhook, a note sent to the webhook is never queued', () async {
      await sentToWebhook('w1', at);
      await store.queueEarlier();
      expect([await store.outbox(), await store.earlierCount(fromWebhook: true)], [isEmpty, 1]);
    });

    test('a note with a server id, one from elsewhere, or one being deleted never counts', () async {
      await sentToWebhook('n1', at);
      await store.applyPulled([pulledNote('s1', clientId: 'n1', mine: true, text: 'Note n1', recordedAt: at)]);
      await store.applyPulled([pulledNote('s2')]);
      await sentToWebhook('n2', at);
      await store.markDeleted('n2', later);
      expect(await store.earlierCount(fromWebhook: true), 0);
      await store.queueEarlier(fromWebhook: true);
      expect(await store.outbox(), isEmpty);
    });
  });

  group('two destinations', () {
    List<(String, String)> rows(List<OutboxItem> items) => [for (final item in items) (item.route, item.destination)];

    test('a health row and a note row queued with different places get different destinations', () async {
      await store.moveOutbox(relayServer, private: ownWebhook);
      await store.enqueue('notes', {'clientId': 'a'});
      await store.enqueue('health', {'samples': []});
      await store.enqueue('locations', {'points': []});
      await store.enqueue('calendar', {'events': [], 'removed': []});
      await store.enqueue('attachment', {'id': 'f1'});
      expect([await store.destination(), await store.privateDestination()], [relayServer, ownWebhook]);
      expect(rows(await store.outbox()), [('notes', relayServer), ('health', ownWebhook), ('locations', ownWebhook),
        ('calendar', ownWebhook), ('attachment', relayServer)]);
    });

    test('a route filter lists only the notes\' own uploads, or only the private ones, each oldest first', () async {
      await store.enqueue('health', {'samples': []});
      await store.enqueue('notes', {'clientId': 'a'});
      await store.enqueue('locations', {'points': []});
      await store.enqueue(staysRoute, {'stays': []});
      await store.enqueue('calendar', {'events': [], 'removed': []});
      await store.enqueue(noteUpdate, {'clientId': 'a'});
      await store.enqueue(noteDelete, {'clientId': 'b'});
      await store.enqueue('attachment', {'id': 'f1'});
      List<String> routes(List<OutboxItem> items) => [for (final item in items) item.route];
      expect(routes(await store.outbox(private: false)), ['notes', noteUpdate, noteDelete, 'attachment']);
      expect(routes(await store.outbox(private: true)), ['health', 'locations', staysRoute, 'calendar']);
      expect((await store.outbox()).length, 8);
      expect(await store.outbox(destination: ownWebhook, private: false), isEmpty);
      expect(routes(await store.outbox(destination: relayServer, private: false)).first, 'notes');
    });

    test('a move of only the private place leaves note rows and drops what the calendar sent', () async {
      await store.enqueue('notes', {'clientId': 'a'});
      await store.enqueue('health', {'samples': [{'type': 'steps'}]});
      await store.queueCalendar([{'events': [], 'removed': []}], {'work:a:1': 'hash'}, const []);
      await store.moveOutbox(relayServer, private: ownWebhook);
      expect(rows(await store.outbox()), [('notes', relayServer), ('health', ownWebhook)]);
      expect(await store.calendarSent(), isEmpty);
      // The same place again keeps what the calendar sent.
      await store.queueCalendar([{'events': [], 'removed': []}], {'work:b:1': 'hash'}, const []);
      await store.moveOutbox(relayServer, private: ownWebhook);
      expect(await store.calendarSent(), {'work:b:1': 'hash'});
      // A move of the notes alone keeps the private rows where they are.
      await store.moveOutbox(ownWebhook, private: ownWebhook);
      expect(rows(await store.outbox()), [('notes', ownWebhook), ('health', ownWebhook), ('calendar', ownWebhook)]);
      expect(await store.calendarSent(), {'work:b:1': 'hash'});
    });

    test('a move of the private place forgets when health, points and the calendar last sent', () async {
      final at = DateTime(2026, 11, 9, 9).millisecondsSinceEpoch.toString();
      for (final key in [sentHealth, sentPoints, sentCalendar]) {
        await store.set(key, at);
      }
      // The same place again keeps the times.
      await store.moveOutbox(relayServer, private: relayServer);
      expect([for (final key in [sentHealth, sentPoints, sentCalendar]) await store.sentAt(key)],
        everyElement(isNotNull));
      // A move of the notes alone keeps them too.
      await store.moveOutbox(ownWebhook, private: relayServer);
      expect(await store.sentAt(sentHealth), isNotNull);
      await store.moveOutbox(relayServer, private: ownWebhook);
      expect([for (final key in [sentHealth, sentPoints, sentCalendar]) await store.sentAt(key)], [null, null, null]);
    });

    test('a store from before the private place sends private rows where notes go', () async {
      await store.set('outbox.destination', ownWebhook);
      expect([await store.destination(), await store.privateDestination()], [ownWebhook, ownWebhook]);
      await store.enqueue('health', {'samples': []});
      await store.enqueue('notes', {'clientId': 'a'});
      expect(rows(await store.outbox()), [('health', ownWebhook), ('notes', ownWebhook)]);
      // A move with one place moves both, as before.
      await store.moveOutbox(relayServer);
      expect([await store.privateDestination(), {for (final item in await store.outbox()) item.destination}],
        [relayServer, {relayServer}]);
    });
  });
}
