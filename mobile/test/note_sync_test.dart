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
import 'package:relay_app/sync/background.dart';

import 'fakes.dart';
import 'offline_test.dart' show until;
import 'screens_test.dart' show openFolder, quill, tallScreen;

const _on = Settings(sending: true);

bool _isPull(http.Request request) => request.method == 'GET' && request.url.path == '/apps/relay/api/notes';

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

    test('leaves the note open in the editor, and keeps its place so the next pull reads it again', () async {
      await store.applyPulled([pulledNote('s1', text: 'One')]);
      final server = FakeServer((_) => notesPage([pulledNote('s1', text: 'Two'), pulledNote('s2')], next: 7));
      expect(await syncNotes(store, Sender(server.api), settings: _on, connection: bearer, editing: 'srv:s1'), 2);
      expect([await store.get(noteSyncSeq), await store.hasNote('srv:s2')], [null, isTrue]);
      expect((await store.notes()).firstWhere((note) => note.clientId == 'srv:s1').text, 'One');
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

    test('on return sends what waits first, then pulls', () async {
      final server = FakeServer((request) => _isPull(request) ? notesPage([pulledNote('s1')], next: 1) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await relay.addNote('Buy milk', sendNow: false);
      await relay.resume();
      expect([for (final request in server.requests) (request.method, request.url.path.split('/').last)],
        [('POST', 'notes'), ('GET', 'connections'), ('GET', 'notes')]);
      expect([for (final entry in relay.entries) entry.from], containsAll([null, 'Email']));
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
      await relay.pullNotes();
      expect(shown.toSet().toList(), containsAllInOrder([1, 2, 3]));
    });

    test('a refused key on a pull shows Key refused', () async {
      final server = FakeServer((request) => _isPull(request) ? FakeServer.json({}, 401) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await relay.pullNotes();
      expect(relay.status, SyncStatus.refused);
    });

    test('disconnect deletes the notes from elsewhere and the pull\'s place; notes from this phone stay', () async {
      final server = FakeServer((request) => _isPull(request)
        ? notesPage([pulledNote('s1', recordedAt: DateTime(2020))], next: 3) : FakeServer.ok(request));
      final relay = relayFor(server);
      await sendToServer(relay);
      await relay.addNote('Buy milk');
      await relay.pullNotes();
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
      await tester.runAsync(relay.pullNotes);
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
      await tester.runAsync(relay.pullNotes);
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

    testWidgets('a voice note from another phone shows its words, where it came from, and no Play', (tester) async {
      final server = FakeServer((request) => _isPull(request)
        ? notesPage([pulledNote('s1', text: 'Call the dentist about Thursday', device: "Sam's iPhone", recordedAt: DateTime.now())],
          next: 1)
        : FakeServer.ok(request));
      final relay = await openApp(tester, server);
      await tester.runAsync(relay.pullNotes);
      await tester.pumpAndSettle();
      await openFolder(tester, 'Notes');
      await tester.tap(find.text('Call the dentist about Thursday'));
      await tester.pumpAndSettle();
      expect(quill(tester).document.toPlainText(), 'Call the dentist about Thursday\n');
      expect(find.textContaining("From Sam's iPhone"), findsOneWidget);
      expect(find.text('Play'), findsNothing);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect([find.widgetWithText(MenuItemButton, 'Copy'), find.widgetWithText(MenuItemButton, 'Play')],
        [findsOneWidget, findsNothing]);
    });
  });
}
