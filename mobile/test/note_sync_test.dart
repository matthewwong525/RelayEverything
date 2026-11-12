import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:relay_app/app.dart';
import 'package:relay_app/controller.dart';
import 'package:relay_app/data/api.dart';
import 'package:relay_app/data/connection.dart';
import 'package:relay_app/data/note_sync.dart';
import 'package:relay_app/data/sender.dart';
import 'package:relay_app/data/settings.dart';
import 'package:relay_app/data/store.dart';
import 'package:relay_app/relay.dart';
import 'package:relay_app/screens/note_blocks.dart' show VoicePlayer;
import 'package:relay_app/sync/background.dart';

import 'fakes.dart';
import 'offline_test.dart' show until;
import 'screens_test.dart' show openFolder, quill, tallScreen;

const _on = Settings(sending: true);

bool _isPull(http.Request request) => request.method == 'GET' && request.url.path == '/apps/relay/api/notes';

/// A pull, then the rest of its round: [RelayController.pullNotes] ends with the notes, while health and photos may
/// still send, and a test closes the store only after them.
Future<void> _pullAll(RelayController relay) async {
  await relay.pullNotes();
  await relay.settled();
}

void main() {
  late Store store;
  setUp(() => store = memoryStore());
  tearDown(() => store.close());

  group('a pull of notes', () {
    test('calls nothing with sending off, while it sends to the own webhook, or with no key', () async {
      final server = noNetwork();
      final sender = Sender(server.api);
      for (final settings in [const Settings(), const Settings(sending: true, place: SendPlace.webhook)]) {
        expect(await syncNotes(store, sender, settings: settings, connection: bearer), 0);
      }
      expect(await syncNotes(store, sender, settings: _on, connection: null), 0);
      expect([server.requests, await store.notes()], [isEmpty, isEmpty]);
    });

    test('reads three pages in order with the phone key, and saves the place after each', () async {
      final pages = {
        0: notesPage([pulledNote('s1', recordedAt: DateTime(2026, 11, 5, 8))], next: 4, more: true),
        4: notesPage([pulledNote('s2', recordedAt: DateTime(2026, 11, 5, 9))], next: 9, more: true),
        9: notesPage([pulledNote('s3', recordedAt: DateTime(2026, 11, 5, 10))], next: 12),
        12: notesPage([], next: 12),
      };
      final server = FakeServer((request) => pages[int.parse(request.url.queryParameters['since']!)]!);
      expect(await syncNotes(store, Sender(server.api), settings: _on, connection: bearer), 3);
      expect([for (final request in server.requests) (request.method, request.url.path, request.url.queryParameters['since'])],
        [('GET', '/apps/relay/api/notes', '0'), ('GET', '/apps/relay/api/notes', '4'), ('GET', '/apps/relay/api/notes', '9')]);
      expect(server.requests.first.headers['Authorization'], 'Bearer $pageKey');
      expect([for (final note in await store.notes()) note.clientId], ['srv:s3', 'srv:s2', 'srv:s1']);
      expect(await store.get(noteSyncSeq), '12');
      expect(await syncNotes(store, Sender(server.api), settings: _on, connection: bearer), 0);
      expect(server.requests.last.url.queryParameters['since'], '12');
    });

    test('tells after each page that brought notes, with that page kept, so the list can show it', () async {
      final pages = {
        0: notesPage([pulledNote('s1')], next: 4, more: true),
        4: notesPage([pulledNote('s2'), pulledNote('s3')], next: 9, more: true),
        9: notesPage([], next: 9),
      };
      final server = FakeServer((request) => pages[int.parse(request.url.queryParameters['since']!)]!);
      final kept = <int>[];
      expect(await syncNotes(store, Sender(server.api), settings: _on, connection: bearer,
        onPage: () async => kept.add((await store.notes()).length)), 3);
      expect(kept, [1, 3]);
    });

    test('stops on a refused key (401), with the pages before it kept', () async {
      final server = FakeServer((request) => request.url.queryParameters['since'] == '0'
        ? notesPage([pulledNote('s1')], next: 5, more: true)
        : FakeServer.json({'error': {'code': 'unauthorized'}}, 401));
      await expectLater(syncNotes(store, Sender(server.api), settings: _on, connection: bearer),
        throwsA(isA<ApiException>().having((error) => error.failure, 'failure', Failure.refused)));
      expect([server.requests.length, await store.get(noteSyncSeq), await store.hasNote('srv:s1')], [2, '5', isTrue]);
    });

    test('asks for deleted notes too, and a note deleted elsewhere leaves the phone', () async {
      await store.applyPulled([pulledNote('s1'), pulledNote('s2')]);
      final server = FakeServer((_) => notesPage([{'id': 's1', 'clientId': null, 'deleted': true}], next: 3));
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect(server.requests.single.url.queryParameters, {'since': '0', 'limit': '100', 'deleted': '1'});
      expect([[for (final note in await store.notes()) note.clientId], await store.get(noteSyncSeq)], [['srv:s2'], '3']);
    });

    test('takes a pulled pin that changed later than the phone\'s, when no pin of the note waits', () async {
      await store.applyPulled([pulledNote('s1', pinned: true, pinChangedAt: DateTime(2026, 11, 5, 9))]);
      await store.pinNote('srv:s1', false, send: false, at: DateTime(2026, 11, 5, 10));
      final server = FakeServer((_) => notesPage([pulledNote('s1', pinned: true, pinChangedAt: DateTime(2026, 11, 5, 11))],
        next: 2));
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect([(await store.notes()).single.pinned, await store.outbox()], [true, isEmpty]);
    });

    test('drops a waiting pin older than the pulled one, which wins, as the server would refuse the older', () async {
      await store.applyPulled([pulledNote('s1', pinned: false)]);
      await store.pinNote('srv:s1', true, send: true, at: DateTime(2026, 11, 5, 9));
      final server = FakeServer((_) => notesPage([pulledNote('s1', pinned: false, pinChangedAt: DateTime(2026, 11, 5, 10))],
        next: 2));
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect([(await store.notes()).single.pinned, await store.outbox()], [false, isEmpty]);
    });

    test('keeps a waiting pin newer than the pulled one, which then goes', () async {
      await store.applyPulled([pulledNote('s1', pinned: true, pinChangedAt: DateTime(2026, 11, 5, 9))]);
      await store.pinNote('srv:s1', false, send: true, at: DateTime(2026, 11, 5, 10));
      final server = FakeServer((_) => notesPage([pulledNote('s1', pinned: true, pinChangedAt: DateTime(2026, 11, 5, 9))],
        next: 2));
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect([(await store.notes()).single.pinned, [for (final item in await store.outbox()) (item.route, item.body['id'])]],
        [false, [(notePin, 's1')]]);
    });

    test('leaves the note open in the editor, and keeps its place so the next pull reads it again', () async {
      await store.applyPulled([pulledNote('s1', text: 'One')]);
      final server = FakeServer((_) => notesPage([pulledNote('s1', text: 'Two'), pulledNote('s2')], next: 7));
      expect(await syncNotes(store, Sender(server.api), settings: _on, connection: bearer, editing: 'srv:s1'), 2);
      expect([await store.get(noteSyncSeq), await store.hasNote('srv:s2')], [null, isTrue]);
      expect((await store.notes()).firstWhere((note) => note.clientId == 'srv:s1').text, 'One');
    });

    test('keeps its place for a note deleted elsewhere while marked deleted here, so after Undo the next pull deletes it',
        () async {
      await store.applyPulled([pulledNote('s1')]);
      await store.markDeleted('srv:s1', DateTime(2026, 11, 5));
      final server = FakeServer((_) => notesPage([{'id': 's1', 'clientId': null, 'deleted': true}], next: 3));
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect([await store.get(noteSyncSeq), await store.hasNote('srv:s1')], [null, isTrue]);
      await store.undoDelete('srv:s1');
      await syncNotes(store, Sender(server.api), settings: _on, connection: bearer);
      expect([server.requests.last.url.queryParameters['since'], await store.get(noteSyncSeq), await store.notes()],
        ['0', '3', isEmpty]);
    });
  });

  test('ends the background round, after the outbox sent', () async {
    await store.set(settingsKey, _on.encode());
    await store.addNote(LocalNote(clientId: 'n1', text: 'Buy milk', createdAt: DateTime(2026, 11, 5)), send: true);
    final server = FakeServer((request) => _isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request));
    expect(await backgroundRound(store, connection: bearer, health: FakeHealth(), sender: Sender(server.api), pull: true), isTrue);
    expect([for (final request in server.requests) (request.method, request.url.path.split('/').last)],
      [('POST', 'notes'), ('GET', 'notes')]);
    expect([await store.hasNote('srv:s1'), await store.get(noteSyncSeq)], [isTrue, '1']);
  });

  group('the app', () {
    late MemoryStorage storage;
    setUp(() => storage = MemoryStorage());

    RelayController relayFor(FakeServer server, {Directory? folder, FileOpener? opener}) => RelayController(store: store,
      vault: KeyVault(storage), places: FakePlaces(), health: FakeHealth(), apiFor: server.api,
      folder: folder == null ? null : () async => folder, opener: opener);

    Future<void> sendToServer(RelayController relay) async {
      await KeyVault(storage).save(bearer);
      await store.set(settingsKey, _on.encode());
      await relay.load();
    }

    test('on return sends what waits first, then pulls, then reads the names', () async {
      final server = FakeServer((request) => _isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await relay.addNote('Buy milk', sendNow: false);
      await relay.resume();
      await relay.settled();
      expect([for (final request in server.requests) (request.method, request.url.path.split('/').last)],
        [('POST', 'notes'), ('GET', 'notes'), ('GET', 'connections')]);
      expect([for (final entry in relay.entries) entry.from], containsAll([null, 'Email']));
    });

    test('a note deleted on another phone leaves the list at the next pull', () async {
      var deleted = false;
      final server = FakeServer((request) => !_isPull(request) ? FakeServer.ok(request)
        : notesPage(deleted ? [{'id': 's1', 'clientId': null, 'deleted': true}] : [pulledNote('s1')], next: deleted ? 2 : 1));
      final relay = relayFor(server);
      await sendToServer(relay);
      await _pullAll(relay);
      expect([for (final entry in relay.entries) entry.text], ['Flight moved to 9:40']);
      deleted = true;
      await _pullAll(relay);
      expect(relay.entries, isEmpty);
    });

    test('a first pull of several pages shows each page in the list as it lands', () async {
      final pages = {
        0: notesPage([pulledNote('s1')], next: 1, more: true),
        1: notesPage([pulledNote('s2')], next: 2, more: true),
        2: notesPage([pulledNote('s3')], next: 3),
      };
      final server = FakeServer((request) => _isPull(request)
        ? pages[int.parse(request.url.queryParameters['since']!)]! : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      final shown = <int>[];
      relay.addListener(() => shown.add(relay.entries.length));
      await _pullAll(relay);
      expect(shown.toSet().toList(), containsAllInOrder([1, 2, 3]));
    });

    test('a pin made elsewhere shows at the next pull, and a pin here goes as PUT notes/pin by the server id', () async {
      var pinned = true;
      final server = FakeServer((request) => _isPull(request)
        ? notesPage([pulledNote('s1', pinned: pinned, pinChangedAt: DateTime(2026, 11, 5, pinned ? 9 : 10))], next: pinned ? 1 : 2)
        : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await _pullAll(relay);
      expect(relay.entries.single.pinned, isTrue);
      pinned = false;
      await _pullAll(relay);
      expect(relay.entries.single.pinned, isFalse);
      await relay.pinNote('srv:s1', true);
      await relay.settled();
      final put = server.requests.singleWhere((request) => request.method == 'PUT');
      expect([put.url.path, (jsonDecode(put.body) as Map)['id'], (jsonDecode(put.body) as Map)['pinned']],
        ['/apps/relay/api/notes/pin', 's1', true]);
      expect([relay.entries.single.pinned, await store.outbox()], [true, isEmpty]);
    });

    test('a pin with sending off stays on the phone and calls nothing', () async {
      final server = noNetwork();
      final relay = relayFor(server);
      await relay.load();
      await relay.addNote('Door code');
      final id = relay.entries.single.id;
      await relay.pinNote(id, true);
      expect([relay.entries.single.pinned, await store.outbox(), server.requests], [true, isEmpty, isEmpty]);
      await relay.pinNote(id, false);
      expect([relay.entries.single.pinned, await store.outbox(), server.requests], [false, isEmpty, isEmpty]);
    });

    test('a pin made while sending was off goes as PUT notes/pin once sending turns on, though no pull brings the note',
        () async {
      var pulled = false;
      final server = FakeServer((request) {
        if (!_isPull(request)) return FakeServer.ok(request);
        final first = !pulled;
        pulled = true;
        return notesPage(first ? [pulledNote('s1', pinned: false)] : [], next: 1);
      });
      final relay = relayFor(server);
      await sendToServer(relay);
      await _pullAll(relay);
      await relay.stopSending();
      await relay.pinNote('srv:s1', true);
      expect(server.requests.where((request) => request.method == 'PUT'), isEmpty);
      expect(await relay.startSending(sendEarlier: false), isNull);
      await relay.settled();
      final put = server.requests.singleWhere((request) => request.method == 'PUT');
      expect([(jsonDecode(put.body) as Map)['id'], (jsonDecode(put.body) as Map)['pinned']], ['s1', true]);
      expect([relay.entries.single.pinned, await store.outbox()], [true, isEmpty]);
    });

    test('a refused key on a pull shows Key refused', () async {
      final server = FakeServer((request) => _isPull(request) ? FakeServer.json({}, 401) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await _pullAll(relay);
      expect(relay.status, SyncStatus.refused);
    });

    test('disconnect deletes the notes from elsewhere and the pull\'s place; notes from this phone stay', () async {
      final server = FakeServer((request) => _isPull(request)
        ? notesPage([pulledNote('s1', recordedAt: DateTime(2020))], next: 3) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await relay.addNote('Buy milk');
      await _pullAll(relay);
      expect([for (final entry in relay.entries) (entry.text, entry.from)], [('Buy milk', null), ('Flight moved to 9:40', 'Email')]);
      expect(await store.get(noteSyncSeq), '3');
      await relay.disconnect();
      expect([for (final entry in relay.entries) entry.text], ['Buy milk']);
      expect(await store.get(noteSyncSeq), isNull);
    });

    Future<RelayController> openApp(WidgetTester tester, FakeServer server, {Directory? folder, FileOpener? opener}) async {
      final relay = relayFor(server, folder: folder, opener: opener);
      await tester.runAsync(() => sendToServer(relay));
      tallScreen(tester);
      await tester.pumpWidget(RelayApp(relay: relay));
      return relay;
    }

    testWidgets('a pull-down on Notes shows a new note from the server, with where it came from', (tester) async {
      var notes = <Map<String, dynamic>>[];
      final server = FakeServer((request) => _isPull(request) ? notesPage(notes, next: notes.length) : FakeServer.ok(request));
      final relay = await openApp(tester, server);
      await openFolder(tester, 'Notes');
      expect(find.text('No notes yet'), findsOneWidget);
      notes = [pulledNote('s1', recordedAt: DateTime.now())];
      await tester.drag(find.text('No notes yet'), const Offset(0, 300));
      await tester.pump();
      // The pull-down's pull reads the store in real time: wait for that same pull, which a second call joins.
      await tester.runAsync(() => _pullAll(relay));
      await tester.pumpAndSettle();
      expect(relay.entries, isNotEmpty);
      expect(find.text('Flight moved to 9:40'), findsOneWidget);
      expect(find.textContaining('· Email'), findsOneWidget);
      expect(server.requests.where(_isPull), hasLength(1));
    });

    testWidgets('one tap on a file from elsewhere downloads that one file and opens it', (tester) async {
      final folder = tempFolder();
      final opened = <String>[];
      final server = FakeServer((request) => switch (request.url.path) {
        '/apps/relay/api/notes' when request.method == 'GET' => notesPage([pulledNote('s1', recordedAt: DateTime.now(), files: [
          {'id': 'f1', 'name': 'ticket.pdf', 'type': 'application/pdf', 'size': 3, 'ready': true},
          {'id': 'f2', 'name': 'map.pdf', 'type': 'application/pdf', 'size': 4, 'ready': true},
        ])], next: 1),
        '/apps/relay/api/attachment' => http.Response('pdf', 200, headers: {'content-type': 'application/pdf'}),
        _ => FakeServer.ok(request),
      });
      final relay = await openApp(tester, server, folder: folder, opener: (file, type) async {
        opened.add(file.path);
        return true;
      });
      await tester.runAsync(() => _pullAll(relay));
      await tester.pumpAndSettle();
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Flight moved to 9:40'));
      await tester.pumpAndSettle();
      expect([find.text('3 B · Download'), find.text('4 B · Download')], [findsOneWidget, findsOneWidget]);
      await tester.tap(find.text('ticket.pdf'));
      await until(tester, () => opened.isNotEmpty);
      await tester.pumpAndSettle();
      expect([for (final request in server.requests) if (request.url.path.endsWith('/attachment')) request.url.queryParameters['id']],
        ['f1']);
      expect([opened.single, File(opened.single).readAsStringSync()], [endsWith('attachments/f1.pdf'), 'pdf']);
      expect([find.text('3 B · Download'), find.text('4 B · Download')], [findsNothing, findsOneWidget]);
    });

    testWidgets('a voice note from another phone shows its words, where it came from, and no player', (tester) async {
      final server = FakeServer((request) => _isPull(request)
        ? notesPage([pulledNote('s1', text: 'Call the dentist about Thursday', device: "Sam's iPhone", recordedAt: DateTime.now())],
          next: 1)
        : FakeServer.ok(request));
      final relay = await openApp(tester, server);
      await tester.runAsync(() => _pullAll(relay));
      await tester.pumpAndSettle();
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Call the dentist about Thursday'));
      await tester.pumpAndSettle();
      expect(quill(tester).document.toPlainText(), 'Call the dentist about Thursday\n');
      expect(find.textContaining("From Sam's iPhone"), findsOneWidget);
      expect([find.byType(VoicePlayer), find.byTooltip('Play')], everyElement(findsNothing));
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect([find.widgetWithText(MenuItemButton, 'Copy'), find.widgetWithText(MenuItemButton, 'Play')],
        [findsOneWidget, findsNothing]);
    });
  });
}
